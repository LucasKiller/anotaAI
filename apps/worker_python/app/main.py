import logging
import time
from uuid import UUID

from redis.exceptions import RedisError

from app.database import SessionLocal, init_db
from app.jobs.pipeline import PipelineProcessor
from app.logging_config import setup_logging
from app.queue import RedisQueueConsumer

setup_logging()
logger = logging.getLogger(__name__)


def run_worker() -> None:
    init_db()
    consumer = RedisQueueConsumer()
    logger.info("Worker started; waiting for jobs")

    while True:
        try:
            message = consumer.pop(timeout=5)
        except (RedisError, TimeoutError):
            logger.exception(
                "Redis unavailable while reading queue. url=%s. Retrying in 3s",
                consumer.redis_url,
            )
            time.sleep(3)
            continue

        if not message:
            continue

        try:
            job_id = UUID(message.job_id)
            recording_id = UUID(message.recording_id)
        except ValueError:
            logger.exception("Invalid queue payload: %s", message)
            continue

        logger.info("Picked up job %s (%s)", job_id, message.job_type)
        with SessionLocal() as db:
            processor = PipelineProcessor(db)
            try:
                processor.run(job_id=job_id, recording_id=recording_id)
            except Exception:
                logger.exception("Pipeline failed for job=%s recording=%s", job_id, recording_id)
                time.sleep(1)


if __name__ == "__main__":
    run_worker()
