from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import requests
from requests import Response
from requests.exceptions import RequestException

from app.config import get_settings

settings = get_settings()


@dataclass
class GatewayTextResult:
    text: str
    model: str
    usage: dict[str, Any] | None = None


class LlmProviderError(RuntimeError):
    """Raised when an OpenAI-compatible provider fails or returns an invalid payload."""


class OpenAICompatibleClient:
    def __init__(
        self,
        *,
        base_url: str | None = None,
        api_key: str | None = None,
        model: str | None = None,
        timeout_seconds: int | None = None,
    ) -> None:
        self.base_url = (base_url or settings.llm_base_url).rstrip("/")
        self.api_key = api_key or settings.llm_api_key
        self.model = model or settings.llm_model
        self.timeout_seconds = timeout_seconds or settings.llm_timeout_seconds

    def create_response(
        self,
        *,
        input_text: str,
        instructions: str | None = None,
        max_output_tokens: int | None = None,
        temperature: float | None = None,
    ) -> GatewayTextResult:
        payload: dict[str, Any] = {
            "model": self.model,
            "input": input_text,
            "stream": False,
        }
        if instructions:
            payload["instructions"] = instructions
        if max_output_tokens is not None:
            payload["max_output_tokens"] = max_output_tokens
        if temperature is not None:
            payload["temperature"] = temperature

        try:
            data = self._post("/v1/responses", payload)
            return GatewayTextResult(
                text=self._extract_response_text(data),
                model=str(data.get("model") or self.model),
                usage=data.get("usage"),
            )
        except LlmProviderError as exc:
            if not self._supports_responses_fallback(exc):
                raise

        fallback_messages = self._response_as_chat_messages(instructions=instructions, input_text=input_text)
        return self.create_chat_completion(
            messages=fallback_messages,
            temperature=temperature,
            max_completion_tokens=max_output_tokens,
        )

    def create_chat_completion(
        self,
        *,
        messages: list[dict[str, Any]],
        temperature: float | None = None,
        max_completion_tokens: int | None = None,
    ) -> GatewayTextResult:
        data = self._post_chat_completions(
            messages=messages,
            temperature=temperature,
            max_completion_tokens=max_completion_tokens,
        )
        return GatewayTextResult(
            text=self._extract_chat_text(data),
            model=str(data.get("model") or self.model),
            usage=data.get("usage"),
        )

    def _post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        if not self.api_key:
            raise LlmProviderError("Nenhuma API key de LLM foi configurada.")

        try:
            response = requests.post(
                self._compose_url(path),
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
                json=payload,
                timeout=self.timeout_seconds,
            )
        except RequestException as exc:
            raise LlmProviderError("Falha de rede ao chamar o provedor de IA.") from exc

        if response.status_code >= 400:
            raise LlmProviderError(self._error_message(response))

        try:
            data = response.json()
        except ValueError as exc:
            raise LlmProviderError("O provedor de IA retornou JSON invalido.") from exc

        if not isinstance(data, dict):
            raise LlmProviderError("O provedor de IA retornou payload inesperado.")
        return data

    def _post_chat_completions(
        self,
        *,
        messages: list[dict[str, Any]],
        temperature: float | None,
        max_completion_tokens: int | None,
    ) -> dict[str, Any]:
        base_payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "stream": False,
        }
        if temperature is not None:
            base_payload["temperature"] = temperature

        token_fields = [None]
        if max_completion_tokens is not None:
            token_fields = ["max_completion_tokens", "max_tokens"]

        last_error: LlmProviderError | None = None
        for token_field in token_fields:
            payload = dict(base_payload)
            if token_field is not None:
                payload[token_field] = max_completion_tokens
            try:
                return self._post("/v1/chat/completions", payload)
            except LlmProviderError as exc:
                last_error = exc
                if not self._should_retry_chat_tokens(exc, token_field):
                    raise

        if last_error is not None:
            raise last_error
        raise LlmProviderError("Falha ao montar a requisicao de chat.")

    def _extract_response_text(self, data: dict[str, Any]) -> str:
        output = data.get("output")
        if not isinstance(output, list):
            raise LlmProviderError("O provedor de IA nao retornou output na Responses API.")

        chunks: list[str] = []
        for item in output:
            if not isinstance(item, dict):
                continue
            for content in item.get("content") or []:
                if isinstance(content, dict):
                    text = content.get("text")
                    if isinstance(text, str) and text.strip():
                        chunks.append(text.strip())

        text = "\n".join(chunks).strip()
        if not text:
            raise LlmProviderError("O provedor de IA retornou resposta vazia na Responses API.")
        return text

    def _extract_chat_text(self, data: dict[str, Any]) -> str:
        choices = data.get("choices")
        if not isinstance(choices, list) or not choices:
            raise LlmProviderError("O provedor de IA nao retornou choices no chat.")

        first = choices[0]
        if not isinstance(first, dict):
            raise LlmProviderError("O provedor de IA retornou choice invalida no chat.")

        message = first.get("message")
        if not isinstance(message, dict):
            raise LlmProviderError("O provedor de IA nao retornou message no chat.")

        content = message.get("content")
        if not isinstance(content, str) or not content.strip():
            raise LlmProviderError("O provedor de IA retornou mensagem vazia no chat.")
        return content.strip()

    def _compose_url(self, path: str) -> str:
        normalized_base = self.base_url.rstrip("/")
        if normalized_base.endswith("/v1") and path.startswith("/v1/"):
            return f"{normalized_base}{path[3:]}"
        return f"{normalized_base}{path}"

    def _supports_responses_fallback(self, error: LlmProviderError) -> bool:
        message = str(error).lower()
        return "404" in message or "not found" in message or "responses" in message

    def _should_retry_chat_tokens(self, error: LlmProviderError, token_field: str | None) -> bool:
        if token_field is None:
            return False
        message = str(error).lower()
        if token_field == "max_tokens":
            return "max_tokens" in message and "max_completion_tokens" in message
        if token_field == "max_completion_tokens":
            return "max_completion_tokens" in message and "max_tokens" in message
        return False

    def _response_as_chat_messages(self, *, instructions: str | None, input_text: str) -> list[dict[str, str]]:
        messages: list[dict[str, str]] = []
        if instructions:
            messages.append({"role": "system", "content": instructions})
        messages.append({"role": "user", "content": input_text})
        return messages

    def _error_message(self, response: Response) -> str:
        try:
            payload = response.json()
        except ValueError:
            payload = None

        if isinstance(payload, dict):
            detail = payload.get("detail")
            if isinstance(detail, str) and detail.strip():
                return detail.strip()

        raw = response.text.strip()
        if raw:
            return raw
        return f"O provedor de IA respondeu com HTTP {response.status_code}."


AiGatewayError = LlmProviderError
AiGatewayClient = OpenAICompatibleClient
