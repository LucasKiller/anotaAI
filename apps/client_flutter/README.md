# client_flutter

Frontend Flutter do AnotaAi com:

- login e cadastro;
- dashboard de gravações;
- criação de gravação;
- upload de áudio por arquivo;
- disparo de processamento;
- leitura de transcrição, resumo e mapa mental.

## Rodar local (web)

1. Garantir API + worker ativos.
2. Entrar na pasta e instalar deps:

```bash
cd apps/client_flutter
flutter pub get
```

3. Rodar no navegador apontando para tua API:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/v1
```

## Observações

- Para rodar no navegador em porta diferente da API, a API já aceita CORS por `CORS_ORIGINS`.
- Em produção, defina `API_BASE_URL` para o domínio real da API.
- Gravação direta por microfone no browser ainda não está implementada nesta etapa.
