from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import requests
from requests import Response
from requests.exceptions import RequestException

from app.core.config import get_settings

settings = get_settings()


@dataclass
class GatewayTextResult:
    text: str
    model: str
    usage: dict[str, Any] | None = None


class AiGatewayError(RuntimeError):
    """Raised when the AI Gateway request fails or returns an invalid payload."""


class AiGatewayClient:
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

        data = self._post("/v1/responses", payload)
        return GatewayTextResult(
            text=self._extract_response_text(data),
            model=str(data.get("model") or self.model),
            usage=data.get("usage"),
        )

    def create_chat_completion(
        self,
        *,
        messages: list[dict[str, Any]],
        temperature: float | None = None,
        max_completion_tokens: int | None = None,
    ) -> GatewayTextResult:
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "stream": False,
        }
        if temperature is not None:
            payload["temperature"] = temperature
        if max_completion_tokens is not None:
            payload["max_completion_tokens"] = max_completion_tokens

        data = self._post("/v1/chat/completions", payload)
        return GatewayTextResult(
            text=self._extract_chat_text(data),
            model=str(data.get("model") or self.model),
            usage=data.get("usage"),
        )

    def _post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        if not self.api_key:
            raise AiGatewayError("LLM_API_KEY nao configurada para o AI Gateway.")

        try:
            response = requests.post(
                f"{self.base_url}{path}",
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
                json=payload,
                timeout=self.timeout_seconds,
            )
        except RequestException as exc:
            raise AiGatewayError("Falha de rede ao chamar o AI Gateway.") from exc

        if response.status_code >= 400:
            raise AiGatewayError(self._error_message(response))

        try:
            data = response.json()
        except ValueError as exc:
            raise AiGatewayError("AI Gateway retornou JSON invalido.") from exc

        if not isinstance(data, dict):
            raise AiGatewayError("AI Gateway retornou payload inesperado.")
        return data

    def _extract_response_text(self, data: dict[str, Any]) -> str:
        output = data.get("output")
        if not isinstance(output, list):
            raise AiGatewayError("AI Gateway nao retornou output na Responses API.")

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
            raise AiGatewayError("AI Gateway retornou resposta vazia na Responses API.")
        return text

    def _extract_chat_text(self, data: dict[str, Any]) -> str:
        choices = data.get("choices")
        if not isinstance(choices, list) or not choices:
            raise AiGatewayError("AI Gateway nao retornou choices no chat.")

        first = choices[0]
        if not isinstance(first, dict):
            raise AiGatewayError("AI Gateway retornou choice invalida no chat.")

        message = first.get("message")
        if not isinstance(message, dict):
            raise AiGatewayError("AI Gateway nao retornou message no chat.")

        content = message.get("content")
        if not isinstance(content, str) or not content.strip():
            raise AiGatewayError("AI Gateway retornou mensagem vazia no chat.")
        return content.strip()

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
        return f"AI Gateway respondeu com HTTP {response.status_code}."
