from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from pathlib import PurePosixPath
import re
import unicodedata
from uuid import UUID, uuid4

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from botocore.config import Config

from app.core.config import get_settings

settings = get_settings()


@dataclass
class UploadedObject:
    bucket: str
    object_key: str
    size_bytes: int
    checksum_sha256: str


class StorageUploadError(Exception):
    """Raised when upload to object storage fails."""


class S3Storage:
    def __init__(self) -> None:
        self._client = boto3.client(
            "s3",
            endpoint_url=settings.s3_endpoint,
            aws_access_key_id=settings.s3_access_key,
            aws_secret_access_key=settings.s3_secret_key,
            region_name=settings.s3_region,
            config=Config(
                connect_timeout=settings.s3_connect_timeout_seconds,
                read_timeout=settings.s3_read_timeout_seconds,
                retries={"max_attempts": 2, "mode": "standard"},
                s3={"addressing_style": "path" if settings.s3_force_path_style else "auto"},
            ),
        )
        self._client.meta.events.register("before-sign.s3.PutObject", self._remove_expect_header)

    def _object_key(self, user_id: UUID, recording_id: UUID, filename: str) -> str:
        safe_name = self._safe_filename(filename)
        return str(
            PurePosixPath("users")
            / str(user_id)
            / "recordings"
            / str(recording_id)
            / "original"
            / safe_name
        )

    def _safe_filename(self, filename: str) -> str:
        normalized = unicodedata.normalize("NFKD", filename).encode("ascii", "ignore").decode("ascii")
        normalized = normalized.replace(" ", "_")
        cleaned = re.sub(r"[^A-Za-z0-9._-]", "", normalized)
        cleaned = cleaned.strip("._")

        if "." in cleaned:
            stem, ext = cleaned.rsplit(".", 1)
            stem = stem[:64] or "audio"
            ext = ext[:10]
            final_name = f"{stem}.{ext}"
        else:
            final_name = (cleaned[:64] or "audio") + ".bin"

        return f"{uuid4().hex}_{final_name}"

    def _remove_expect_header(self, request, **kwargs) -> None:
        # Some reverse proxies in front of MinIO mishandle "Expect: 100-continue".
        if "Expect" in request.headers:
            del request.headers["Expect"]

    def upload_recording_file(
        self,
        *,
        user_id: UUID,
        recording_id: UUID,
        filename: str,
        content_type: str,
        content: bytes,
    ) -> UploadedObject:
        object_key = self._object_key(user_id=user_id, recording_id=recording_id, filename=filename)
        digest = sha256(content).hexdigest()

        try:
            self._client.put_object(
                Bucket=settings.s3_bucket,
                Key=object_key,
                Body=content,
                ContentType=content_type,
                Metadata={"sha256": digest},
            )
        except (ClientError, BotoCoreError) as exc:
            raise StorageUploadError(
                f"Upload to storage failed for endpoint={settings.s3_endpoint} bucket={settings.s3_bucket}"
            ) from exc

        return UploadedObject(
            bucket=settings.s3_bucket,
            object_key=object_key,
            size_bytes=len(content),
            checksum_sha256=digest,
        )
