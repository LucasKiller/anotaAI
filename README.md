# AnotaAí

Base inicial do MVP com arquitetura preparada para processamento assíncrono de gravações, storage S3-compatible e chat por gravação.

## Stack

- Frontend: Flutter (`apps/client_flutter`)
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

4. Frontend Flutter (dev):

```bash
cd apps/client_flutter
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/v1
```

## Rodar API e Worker (local)

Se quiser rodar só infra no Docker e executar API/worker no host:

```bash
docker compose -f infra/compose/docker-compose.yml up -d postgres redis minio minio_init
```

API (Linux/macOS):

```bash
python3 -m venv apps/api_python/venv
source apps/api_python/venv/bin/activate
pip install -r apps/api_python/requirements.txt
uvicorn app.main:app --app-dir apps/api_python --host 0.0.0.0 --port 8000 --reload
```

API (Windows CMD):

```bat
python -m venv apps\api_python\venv
apps\api_python\venv\Scripts\activate
pip install -r apps\api_python\requirements.txt
uvicorn app.main:app --app-dir apps/api_python --host 0.0.0.0 --port 8000 --reload
```

Worker (Linux/macOS):

```bash
python3 -m venv apps/worker_python/venv
source apps/worker_python/venv/bin/activate
pip install -r apps/worker_python/requirements.txt
PYTHONPATH=apps/worker_python python -m app.main
```

Worker (Windows CMD):

```bat
python -m venv apps\worker_python\venv
apps\worker_python\venv\Scripts\activate
pip install -r apps\worker_python\requirements.txt
set PYTHONPATH=apps\worker_python && python -m app.main
```

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
- `GET /v1/recordings/{id}/chat/sessions`
- chat por sessão em `/v1/chat/sessions/...`

## Endpoints de edição já disponíveis

- `PATCH /v1/me` (atualiza apenas `name`)
- `PATCH /v1/recordings/{id}` (atualiza título/descrição/idioma)
- `DELETE /v1/recordings/{id}`

`email` e `password` não possuem endpoint de alteração nesta fase.

## Serviços no Compose

- `client`: Nginx para servir `apps/client_flutter/web` (use build Flutter para produção)
- `api`: FastAPI
- `worker`: processamento assíncrono
- `postgres`: `pgvector/pgvector:pg16`
- `redis`: fila/cache
- `minio`: object storage
- `minio_init`: cria bucket privado `anotaai-private`

## Observações de implementação

- Áudios vão para MinIO; metadados ficam no Postgres.
- O pipeline do worker usa `faster-whisper` para transcrição real quando `TRANSCRIPTION_PROVIDER=local_whisper`.
- Para transcrição local funcionar, `ffmpeg` precisa estar instalado no host/container do worker.
- Para resumo, mapa mental e chat com provider OpenAI-compatible global, configure `LLM_PROVIDER`, `LLM_BASE_URL`, `LLM_API_KEY` e `LLM_MODEL`.
- Para criptografar com seguranca as chaves de IA dos usuarios, configure `AI_SETTINGS_ENCRYPTION_KEY` com o mesmo valor na API e no worker.
- O `LLM_BASE_URL` deve apontar para o prefixo do seu gateway, por exemplo `https://api.inovv.co/ai/v1/dev`, pois a aplicação chama `/v1/responses` e `/v1/chat/completions` a partir dele.
- Os pontos de extensão para Whisper/Ollama estão separados em `apps/worker_python/app/jobs/*`.
- A API já está organizada com `services`, `repositories` e `integrations`.

## Chave de IA por usuario

Cada usuario pode salvar a propria configuracao de IA e trocar entre:

- `openai`
- `openai_compatible`

Quando houver configuracao do usuario, ela tem prioridade para:

- resumo
- mapa mental
- chat

Se nao houver override do usuario, a aplicacao continua usando a configuracao global de `.env`.

Endpoints:

- `GET /v1/me/ai-settings`
- `PUT /v1/me/ai-settings`
- `DELETE /v1/me/ai-settings`

Payload de exemplo:

```json
{
  "provider_type": "openai_compatible",
  "base_url": "https://seu-provedor.com/v1",
  "model": "gpt-4.1-mini",
  "api_key": "sk-..."
}
```

## Próximos passos recomendados

1. Melhorar estratégia de chunking e sumarização para textos longos.
2. Adicionar embeddings reais + índice vetorial (`HNSW`).
3. Implementar presigned upload para arquivos grandes.
4. Substituir `create_all` por migrations Alembic versionadas.
5. Evoluir renderização visual do mapa mental no frontend.
