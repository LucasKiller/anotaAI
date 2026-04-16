from pathlib import Path
import tempfile
import sys
from urllib.parse import urlsplit, urlunsplit

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.config import get_settings

settings = get_settings()


def _normalize_endpoint_url(endpoint_url: str) -> str:
    if sys.platform != "win32":
        return endpoint_url

    parsed = urlsplit(endpoint_url)
    if parsed.hostname != "localhost":
        return endpoint_url

    netloc = parsed.netloc.replace("localhost", "127.0.0.1", 1)
    return urlunsplit((parsed.scheme, netloc, parsed.path, parsed.query, parsed.fragment))


class StorageDownloadError(RuntimeError):
    """Raised when the worker cannot download an object from storage."""


class S3StorageClient:
    def __init__(self) -> None:
        endpoint_url = _normalize_endpoint_url(settings.s3_endpoint)
        self._client = boto3.client(
            's3',
            endpoint_url=endpoint_url,
            aws_access_key_id=settings.s3_access_key,
            aws_secret_access_key=settings.s3_secret_key,
            region_name=settings.s3_region,
            config=Config(
                connect_timeout=settings.s3_connect_timeout_seconds,
                read_timeout=settings.s3_read_timeout_seconds,
                retries={'max_attempts': 2, 'mode': 'standard'},
                s3={'addressing_style': 'path' if settings.s3_force_path_style else 'auto'},
            ),
        )

    def download_to_temp_file(self, *, bucket: str, object_key: str) -> Path:
        suffix = Path(object_key).suffix or '.bin'
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)

        try:
            response = self._client.get_object(Bucket=bucket, Key=object_key)
            body = response['Body']
            try:
                for chunk in iter(lambda: body.read(settings.s3_download_chunk_size), b''):
                    temp.write(chunk)
                temp.flush()
            finally:
                body.close()
        except (ClientError, BotoCoreError, OSError) as exc:
            temp.close()
            Path(temp.name).unlink(missing_ok=True)
            raise StorageDownloadError(
                f"Falha ao baixar arquivo do storage endpoint={settings.s3_endpoint} bucket={bucket}"
            ) from exc
        finally:
            temp.close()

        return Path(temp.name)
