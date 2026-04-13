# AnotaAí

Base inicial do MVP com arquitetura preparada para processamento assíncrono de gravações, storage S3-compatible e chat por gravação.

## Stack

- Frontend: Flutter (placeholder web em `apps/client_flutter/web`)
- API: FastAPI (`apps/api_python`)
- Worker: Python assíncrono com fila Redis (`apps/worker_python`)
- Banco: PostgreSQL + pgvector
- Storage: MinIO (S3-compatible)
- Fila/cache: Redis
- Orquestração: Docker Compose (pronto para Coolify)

## Estrutura

```txt
anotaai/
  apps/
    client_flutter/
    api_python/
    worker_python/
  infra/
    compose/docker-compose.yml
    nginx/client.conf
  docs/
  .env.example
```

## Subir localmente

1. Opcional: copiar variáveis para customizar secrets.

```bash
cp .env.example .env
```

2. Subir stack.

```bash
docker compose -f infra/compose/docker-compose.yml up --build
```

3. API disponível em `http://localhost:8000`.

- Health: `GET /v1/health`
- Docs: `http://localhost:8000/docs`

4. Frontend placeholder em `http://localhost:8080`.

## Fluxo mínimo do MVP

1. `POST /v1/auth/register`
2. `POST /v1/recordings`
3. `POST /v1/recordings/{id}/upload`
4. `POST /v1/recordings/{id}/process`
5. Worker consome fila e gera:
- `transcripts`
- `transcript_segments`
- `artifacts` (`summary`, `mindmap`)
6. Consultar:
- `GET /v1/recordings/{id}/transcript`
- `GET /v1/recordings/{id}/summary`
- `GET /v1/recordings/{id}/mindmap`
- chat por sessão em `/v1/chat/sessions/...`

## Serviços no Compose

- `client`: Nginx com placeholder web
- `api`: FastAPI
- `worker`: processamento assíncrono
- `postgres`: `pgvector/pgvector:pg16`
- `redis`: fila/cache
- `minio`: object storage
- `minio_init`: cria bucket privado `anotaai-private`

## Observações de implementação

- Áudios vão para MinIO; metadados ficam no Postgres.
- O pipeline do worker está em modo **stub** para transcrição/artefatos.
- Os pontos de extensão para Whisper/Ollama estão separados em `apps/worker_python/app/jobs/*`.
- A API já está organizada com `services`, `repositories` e `integrations`.

## Próximos passos recomendados

1. Trocar `transcribe_audio_stub` por Whisper real no worker.
2. Adicionar embeddings reais + índice vetorial (`HNSW`).
3. Implementar presigned upload para arquivos grandes.
4. Substituir `create_all` por migrations Alembic versionadas.
5. Conectar frontend Flutter real em `apps/client_flutter`.
