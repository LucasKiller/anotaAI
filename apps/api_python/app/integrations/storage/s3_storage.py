from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from pathlib import PurePosixPath
from uuid import UUID

import boto3
from botocore.config import Config

from app.core.config import get_settings

settings = get_settings()


@dataclass
class UploadedObject:
    bucket: str
    object_key: str
    size_bytes: int
    checksum_sha256: str


class S3Storage:
    def __init__(self) -> None:
        self._client = boto3.client(
            "s3",
            endpoint_url=settings.s3_endpoint,
            aws_access_key_id=settings.s3_access_key,
            aws_secret_access_key=settings.s3_secret_key,
            region_name=settings.s3_region,
            config=Config(s3={"addressing_style": "path" if settings.s3_force_path_style else "auto"}),
        )

    def _object_key(self, user_id: UUID, recording_id: UUID, filename: str) -> str:
        safe_name = filename.replace(" ", "_") or "audio.bin"
        return str(
            PurePosixPath("users")
            / str(user_id)
            / "recordings"
            / str(recording_id)
            / "original"
            / safe_name
        )

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

        self._client.put_object(
            Bucket=settings.s3_bucket,
            Key=object_key,
            Body=content,
            ContentType=content_type,
            Metadata={"sha256": digest},
        )

        return UploadedObject(
            bucket=settings.s3_bucket,
            object_key=object_key,
            size_bytes=len(content),
            checksum_sha256=digest,
        )
