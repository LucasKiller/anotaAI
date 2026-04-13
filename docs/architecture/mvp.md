# Arquitetura MVP

## Componentes

- Cliente Flutter
- API FastAPI
- Worker Python
- PostgreSQL + pgvector
- Redis
- MinIO (S3-compatible)

## Fluxo principal

1. Usuário cria gravação.
2. Upload do áudio via API.
3. API grava objeto no MinIO.
4. API cria `processing_jobs` e publica payload no Redis.
5. Worker consome payload e processa pipeline.
6. Worker salva transcript, segments e artifacts.
7. API responde consultas de transcript, artifacts e chat.

## Contratos de dados

Os modelos seguem a especificação: `users`, `recordings`, `recording_files`, `transcripts`, `transcript_segments`, `segment_embeddings`, `artifacts`, `chat_sessions`, `chat_messages`, `processing_jobs`, `usage_events`.
