from __future__ import annotations

from dataclasses import dataclass
import json
import re
from typing import Any

from app.config import get_settings
from app.integrations.llm import LlmProviderError, OpenAICompatibleClient
from app.integrations.llm.provider_config import ResolvedLlmConfig

settings = get_settings()

_SUMMARY_CHUNK_CHARS = 5_500
_MINDMAP_CONTEXT_CHARS = 8_000


@dataclass
class GeneratedMarkdownArtifact:
    content: str
    model_name: str


@dataclass
class GeneratedJsonArtifact:
    content: dict[str, Any]
    model_name: str


class ArtifactGenerationError(RuntimeError):
    """Raised when an AI artifact cannot be generated."""


def build_summary_markdown(
    title: str,
    full_text: str,
    segments: list[dict],
    *,
    llm_config: ResolvedLlmConfig | None = None,
) -> GeneratedMarkdownArtifact:
    active_llm_config = llm_config or _default_llm_config()
    if not active_llm_config or not active_llm_config.has_api_key:
        return GeneratedMarkdownArtifact(content=_stub_summary_markdown(title, full_text, segments), model_name="local-stub")

    client = OpenAICompatibleClient(
        base_url=active_llm_config.base_url,
        api_key=active_llm_config.api_key,
        model=active_llm_config.model,
    )
    chunk_contexts = _build_chunk_contexts(full_text, segments, max_chars=_SUMMARY_CHUNK_CHARS)

    try:
        partial_summaries: list[str] = []
        model_name = client.model

        for index, chunk in enumerate(chunk_contexts, start=1):
            partial = client.create_response(
                input_text=chunk,
                instructions=_chunk_summary_instructions(title=title, chunk_index=index, total_chunks=len(chunk_contexts)),
                max_output_tokens=500,
                temperature=0.2,
            )
            partial_summaries.append(partial.text.strip())
            model_name = partial.model

        final = client.create_response(
            input_text=_final_summary_input(title=title, partial_summaries=partial_summaries),
            instructions=_final_summary_instructions(),
            max_output_tokens=900,
            temperature=0.2,
        )
        return GeneratedMarkdownArtifact(content=final.text.strip(), model_name=final.model or model_name)
    except LlmProviderError as exc:
        raise ArtifactGenerationError(f"Falha ao gerar resumo via provedor de IA: {exc}") from exc


def build_mindmap_json(
    title: str,
    full_text: str,
    segments: list[dict],
    summary_markdown: str,
    *,
    llm_config: ResolvedLlmConfig | None = None,
) -> GeneratedJsonArtifact:
    active_llm_config = llm_config or _default_llm_config()
    if not active_llm_config or not active_llm_config.has_api_key:
        return GeneratedJsonArtifact(content=_stub_mindmap_json(title, segments), model_name="local-stub")

    client = OpenAICompatibleClient(
        base_url=active_llm_config.base_url,
        api_key=active_llm_config.api_key,
        model=active_llm_config.model,
    )
    context = _mindmap_context(title=title, summary_markdown=summary_markdown, full_text=full_text, segments=segments)

    try:
        result = client.create_response(
            input_text=context,
            instructions=_mindmap_instructions(),
            max_output_tokens=1_200,
            temperature=0.1,
        )
        parsed = _parse_json_payload(result.text)
    except (LlmProviderError, ValueError):
        try:
            repaired = client.create_response(
                input_text=context,
                instructions=_mindmap_repair_instructions(),
                max_output_tokens=1_200,
                temperature=0.0,
            )
            parsed = _parse_json_payload(repaired.text)
            return GeneratedJsonArtifact(content=_normalize_mindmap(parsed, fallback_title=title), model_name=repaired.model)
        except (LlmProviderError, ValueError) as exc:
            raise ArtifactGenerationError(f"Falha ao gerar mapa mental via provedor de IA: {exc}") from exc

    return GeneratedJsonArtifact(content=_normalize_mindmap(parsed, fallback_title=title), model_name=result.model)


def _default_llm_config() -> ResolvedLlmConfig | None:
    api_key = settings.llm_api_key.strip() if settings.llm_api_key else None
    base_url = settings.llm_base_url.strip().rstrip("/")
    model = settings.llm_model.strip()
    if not api_key or not base_url or not model:
        return None
    return ResolvedLlmConfig(
        source="system",
        provider_type="openai_compatible",
        base_url=base_url,
        model=model,
        api_key=api_key,
        has_api_key=True,
    )


def _build_chunk_contexts(full_text: str, segments: list[dict], *, max_chars: int) -> list[str]:
    if segments:
        chunks: list[str] = []
        current: list[str] = []
        current_size = 0

        for segment in segments:
            line = f"[{_format_ms(segment['start_ms'])}-{_format_ms(segment['end_ms'])}] {segment['text'].strip()}"
            if current and current_size + len(line) + 1 > max_chars:
                chunks.append("\n".join(current))
                current = [line]
                current_size = len(line)
            else:
                current.append(line)
                current_size += len(line) + 1

        if current:
            chunks.append("\n".join(current))
        return chunks

    normalized = full_text.strip()
    if not normalized:
        return [""]

    return [normalized[start : start + max_chars] for start in range(0, len(normalized), max_chars)]


def _chunk_summary_instructions(*, title: str, chunk_index: int, total_chunks: int) -> str:
    return (
        "Voce esta resumindo uma transcricao de audio para o produto AnotaAi.\n"
        f"Titulo da gravacao: {title}.\n"
        f"Parte {chunk_index} de {total_chunks}.\n"
        "Resuma somente o conteudo fornecido.\n"
        "Nao invente fatos, pessoas, datas ou conclusoes ausentes.\n"
        "Responda em Markdown com exatamente estas secoes:\n"
        "## Topicos\n"
        "Use de 3 a 6 bullets curtos.\n"
        "## Detalhes\n"
        "Use 1 paragrafo curto com contexto importante.\n"
        "Mantenha a resposta objetiva."
    )


def _final_summary_input(*, title: str, partial_summaries: list[str]) -> str:
    parts = [f"TITULO: {title}", "", "RESUMOS PARCIAIS:"]
    for index, item in enumerate(partial_summaries, start=1):
        parts.append(f"\n### Parte {index}\n{item.strip()}")
    return "\n".join(parts).strip()


def _final_summary_instructions() -> str:
    return (
        "Consolide os resumos parciais de uma gravacao em um resumo final fiel ao conteudo.\n"
        "Nao invente informacoes.\n"
        "Retorne Markdown com exatamente estas secoes e titulos:\n"
        "# Resumo\n"
        "## Visao geral\n"
        "## Pontos principais\n"
        "## Perguntas e implicacoes\n"
        "Em 'Pontos principais', use de 4 a 8 bullets claros.\n"
        "Em 'Perguntas e implicacoes', cite duvidas abertas, acoes, decisoes ou consequencias quando existirem.\n"
        "Se algo nao estiver claro no conteudo, sinalize a incerteza."
    )


def _mindmap_context(*, title: str, summary_markdown: str, full_text: str, segments: list[dict]) -> str:
    source = summary_markdown.strip()
    if not source:
        source = full_text.strip()

    segment_lines: list[str] = []
    total_size = 0
    for segment in segments:
        line = f"- [{_format_ms(segment['start_ms'])}] {segment['text'].strip()}"
        if total_size + len(line) + 1 > _MINDMAP_CONTEXT_CHARS:
            break
        segment_lines.append(line)
        total_size += len(line) + 1

    parts = [
        f"TITULO: {title}",
        "",
        "RESUMO BASE:",
        source[:_MINDMAP_CONTEXT_CHARS].strip(),
    ]
    if segment_lines:
        parts.extend(["", "TRECHOS DE APOIO:", "\n".join(segment_lines)])
    return "\n".join(parts).strip()


def _mindmap_instructions() -> str:
    return (
        "Transforme o conteudo em um mapa mental JSON valido.\n"
        "Retorne somente JSON, sem markdown, sem comentarios e sem texto adicional.\n"
        "Use exatamente este formato:\n"
        '{'
        '"title": "string", '
        '"nodes": ['
        '{"label": "string", "children": [{"label": "string", "children": []}]}'
        "]}"
        "\n"
        "Regras:\n"
        "- maximo de 5 nos principais.\n"
        "- cada no principal com ate 5 filhos.\n"
        "- labels curtos e especificos.\n"
        "- nao invente conceitos ausentes.\n"
        "- se houver etapas ou categorias, reflita essa estrutura."
    )


def _mindmap_repair_instructions() -> str:
    return (
        "Gere um mapa mental JSON valido a partir do contexto fornecido.\n"
        "Retorne somente JSON puro no formato:\n"
        '{'
        '"title": "string", '
        '"nodes": ['
        '{"label": "string", "children": [{"label": "string", "children": []}]}'
        "]}"
        "\n"
        "Nao use markdown, nao use crases, nao explique."
    )


def _parse_json_payload(raw_text: str) -> dict[str, Any]:
    cleaned = raw_text.strip()
    cleaned = cleaned.removeprefix("```json").removeprefix("```").removesuffix("```").strip()

    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
        if not match:
            raise ValueError("AI Gateway nao retornou JSON valido para o mapa mental.")
        parsed = json.loads(match.group(0))

    if not isinstance(parsed, dict):
        raise ValueError("Mapa mental retornado nao e um objeto JSON.")
    return parsed


def _normalize_mindmap(payload: dict[str, Any], *, fallback_title: str) -> dict[str, Any]:
    nodes = payload.get("nodes")
    if not isinstance(nodes, list):
        nodes = []

    normalized_nodes = [_normalize_node(node) for node in nodes if isinstance(node, dict)]
    normalized_nodes = [node for node in normalized_nodes if node is not None]

    return {
        "title": str(payload.get("title") or fallback_title),
        "nodes": normalized_nodes,
    }


def _normalize_node(node: dict[str, Any]) -> dict[str, Any] | None:
    label = str(node.get("label") or "").strip()
    if not label:
        return None

    children = node.get("children")
    normalized_children: list[dict[str, Any]] = []
    if isinstance(children, list):
        for child in children:
            if isinstance(child, dict):
                normalized = _normalize_node(child)
                if normalized is not None:
                    normalized_children.append(normalized)

    return {
        "label": label,
        "children": normalized_children,
    }


def _format_ms(value: int) -> str:
    total_seconds = max(0, value // 1000)
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60
    if hours:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


def _stub_summary_markdown(title: str, full_text: str, segments: list[dict]) -> str:
    bullets = "\n".join(f"- {segment['text']}" for segment in segments[:5])
    return (
        f"# Resumo: {title}\n\n"
        "## Visao geral\n"
        f"{full_text[:320]}...\n\n"
        "## Pontos principais\n"
        f"{bullets if bullets else '- Sem segmentos disponiveis.'}"
    )


def _stub_mindmap_json(title: str, segments: list[dict]) -> dict[str, Any]:
    children = [{"label": seg["text"][:80], "children": []} for seg in segments[:8]]
    return {
        "title": title,
        "nodes": [
            {
                "label": "Conteudo transcrito",
                "children": children,
            }
        ],
    }
