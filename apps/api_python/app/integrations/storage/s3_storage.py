from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from pathlib import PurePosixPath
import re
import sys
import unicodedata
from urllib.parse import urlsplit, urlunsplit
from uuid import UUID, uuid4

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from botocore.config import Config

from app.core.config import get_settings

settings = get_settings()


def _normalize_endpoint_url(endpoint_url: str) -> str:
    if sys.platform != "win32":
        return endpoint_url

    parsed = urlsplit(endpoint_url)
    if parsed.hostname != "localhost":
        return endpoint_url

    netloc = parsed.netloc.replace("localhost", "127.0.0.1", 1)
    return urlunsplit((parsed.scheme, netloc, parsed.path, parsed.query, parsed.fragment))


@dataclass
class UploadedObject:
    bucket: str
    object_key: str
    size_bytes: int
    checksum_sha256: str


@dataclass
class DownloadedObject:
    content: bytes
    content_type: str | None


class StorageUploadError(Exception):
    """Raised when upload to object storage fails."""


class StorageDownloadError(Exception):
    """Raised when download from object storage fails."""


class S3Storage:
    def __init__(self) -> None:
        endpoint_url = _normalize_endpoint_url(settings.s3_endpoint)
        self._client = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
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
                "Upload to storage failed for "
                f"endpoint={settings.s3_endpoint} bucket={settings.s3_bucket}: {exc}"
            ) from exc

        return UploadedObject(
            bucket=settings.s3_bucket,
            object_key=object_key,
            size_bytes=len(content),
            checksum_sha256=digest,
        )

    def download_recording_file(self, *, bucket: str, object_key: str) -> DownloadedObject:
        try:
            response = self._client.get_object(Bucket=bucket, Key=object_key)
            body = response["Body"]
            try:
                content = body.read()
            finally:
                close = getattr(body, "close", None)
                if callable(close):
                    close()
                release_conn = getattr(body, "release_conn", None)
                if callable(release_conn):
                    release_conn()
        except (ClientError, BotoCoreError) as exc:
            raise StorageDownloadError(
                "Download from storage failed for "
                f"endpoint={settings.s3_endpoint} bucket={bucket}: {exc}"
            ) from exc

        return DownloadedObject(
            content=content,
            content_type=response.get("ContentType"),
        )
