import json

import redis

from app.core.config import get_settings

settings = get_settings()


class RedisQueue:
    def __init__(self) -> None:
        self._client = redis.Redis.from_url(settings.redis_url, decode_responses=True)

    def enqueue(self, payload: dict) -> None:
        self._client.rpush(settings.job_queue_key, json.dumps(payload))
