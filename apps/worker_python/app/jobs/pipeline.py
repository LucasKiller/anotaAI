import logging
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.jobs.artifacts import build_mindmap_json, build_summary_markdown
from app.jobs.chat_index import update_chat_index_stub
from app.jobs.embeddings import build_embeddings_stub
from app.jobs.segmentation import build_segments
from app.jobs.transcription import transcribe_audio_stub
from app.models import Artifact, ProcessingJob, Recording, RecordingFile, Transcript, TranscriptSegment

logger = logging.getLogger(__name__)


class PipelineProcessor:
    def __init__(self, db: Session):
        self.db = db

    def run(self, *, job_id: UUID, recording_id: UUID) -> None:
        job = self.db.get(ProcessingJob, job_id)
        recording = self.db.get(Recording, recording_id)

        if not job:
            raise ValueError(f"processing_job {job_id} not found")
        if not recording:
            raise ValueError(f"recording {recording_id} not found")

        job.status = "running"
        job.started_at = datetime.now(UTC)
        job.attempts = (job.attempts or 0) + 1
        self.db.add(job)

        recording.status = "processing"
        recording.failed_reason = None
        self.db.add(recording)
        self.db.commit()

        try:
            latest_file = self._latest_file(recording.id)
            transcript_text, model_name = transcribe_audio_stub(
                title=recording.title,
                object_key=latest_file.object_key if latest_file else None,
            )

            transcript = self._create_transcript(
                recording_id=recording.id,
                full_text=transcript_text,
                language=recording.language,
                model_name=model_name,
            )

            segments_payload = build_segments(transcript_text)
            self._create_segments(transcript_id=transcript.id, segments_payload=segments_payload)
            build_embeddings_stub(segments_payload)

            summary = build_summary_markdown(recording.title, transcript_text, segments_payload)
            mindmap = build_mindmap_json(recording.title, segments_payload)
            self._create_artifact(recording.id, artifact_type="summary", content_md=summary)
            self._create_artifact(recording.id, artifact_type="mindmap", content_json=mindmap)
            chat_index_result = update_chat_index_stub(str(recording.id))

            recording.status = "ready"
            recording.processed_at = datetime.now(UTC)
            recording.failed_reason = None
            self.db.add(recording)

            job.status = "completed"
            job.finished_at = datetime.now(UTC)
            job.result_json = {
                "transcript_id": str(transcript.id),
                "segments": len(segments_payload),
                "artifacts": ["summary", "mindmap"],
                "chat_index": chat_index_result,
            }
            self.db.add(job)
            self.db.commit()
            logger.info("Pipeline completed for recording=%s job=%s", recording.id, job.id)
        except Exception as exc:
            self.db.rollback()
            self._mark_failed(job_id=job_id, recording_id=recording_id, error_message=str(exc))
            raise

    def _latest_file(self, recording_id: UUID) -> RecordingFile | None:
        stmt = (
            select(RecordingFile)
            .where(RecordingFile.recording_id == recording_id)
            .order_by(RecordingFile.uploaded_at.desc())
            .limit(1)
        )
        return self.db.scalar(stmt)

    def _create_transcript(self, *, recording_id: UUID, full_text: str, language: str | None, model_name: str) -> Transcript:
        next_version = (
            self.db.scalar(select(func.max(Transcript.version)).where(Transcript.recording_id == recording_id)) or 0
        ) + 1

        transcript = Transcript(
            recording_id=recording_id,
            version=next_version,
            full_text=full_text,
            language=language,
            model_name=model_name,
        )
        self.db.add(transcript)
        self.db.flush()
        return transcript

    def _create_segments(self, *, transcript_id: UUID, segments_payload: list[dict]) -> None:
        for payload in segments_payload:
            segment = TranscriptSegment(
                transcript_id=transcript_id,
                segment_index=payload["segment_index"],
                start_ms=payload["start_ms"],
                end_ms=payload["end_ms"],
                text=payload["text"],
                tokens_estimate=payload["tokens_estimate"],
            )
            self.db.add(segment)
        self.db.flush()

    def _create_artifact(
        self,
        recording_id: UUID,
        *,
        artifact_type: str,
        content_md: str | None = None,
        content_json: dict | None = None,
    ) -> None:
        next_version = (
            self.db.scalar(
                select(func.max(Artifact.version)).where(
                    Artifact.recording_id == recording_id,
                    Artifact.artifact_type == artifact_type,
                )
            )
            or 0
        ) + 1

        artifact = Artifact(
            recording_id=recording_id,
            artifact_type=artifact_type,
            version=next_version,
            content_md=content_md,
            content_json=content_json,
            model_name="local-stub",
        )
        self.db.add(artifact)
        self.db.flush()

    def _mark_failed(self, *, job_id: UUID, recording_id: UUID, error_message: str) -> None:
        job = self.db.get(ProcessingJob, job_id)
        recording = self.db.get(Recording, recording_id)

        if job:
            job.status = "failed"
            job.finished_at = datetime.now(UTC)
            job.error_message = error_message
            self.db.add(job)

        if recording:
            recording.status = "failed"
            recording.failed_reason = error_message
            self.db.add(recording)

        self.db.commit()
