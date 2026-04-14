from pathlib import Path
import tempfile

import boto3
from botocore.config import Config

from app.config import get_settings

settings = get_settings()


class S3StorageClient:
    def __init__(self) -> None:
        self._client = boto3.client(
            's3',
            endpoint_url=settings.s3_endpoint,
            aws_access_key_id=settings.s3_access_key,
            aws_secret_access_key=settings.s3_secret_key,
            region_name=settings.s3_region,
            config=Config(
                connect_timeout=5,
                read_timeout=30,
                retries={'max_attempts': 2, 'mode': 'standard'},
                s3={'addressing_style': 'path' if settings.s3_force_path_style else 'auto'},
            ),
        )

    def download_to_temp_file(self, *, bucket: str, object_key: str) -> Path:
        response = self._client.get_object(Bucket=bucket, Key=object_key)
        body = response['Body'].read()

        suffix = Path(object_key).suffix or '.bin'
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        temp.write(body)
        temp.flush()
        temp.close()

        return Path(temp.name)
