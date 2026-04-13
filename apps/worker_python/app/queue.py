import json
from dataclasses import dataclass

import redis

from app.config import get_settings

settings = get_settings()


@dataclass
class QueueMessage:
    job_id: str
    recording_id: str
    user_id: str
    job_type: str


class RedisQueueConsumer:
    def __init__(self) -> None:
        self._client = redis.Redis.from_url(settings.redis_url, decode_responses=True)

    def pop(self, timeout: int = 5) -> QueueMessage | None:
        response = self._client.blpop(settings.job_queue_key, timeout=timeout)
        if not response:
            return None

        _, payload = response
        data = json.loads(payload)
        return QueueMessage(
            job_id=data["job_id"],
            recording_id=data["recording_id"],
            user_id=data["user_id"],
            job_type=data.get("job_type", "pipeline"),
        )
