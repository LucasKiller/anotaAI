def build_summary_markdown(title: str, full_text: str, segments: list[dict]) -> str:
    bullets = "\n".join(f"- {segment['text']}" for segment in segments[:5])
    return (
        f"# Resumo: {title}\n\n"
        "## Visão geral\n"
        f"{full_text[:320]}...\n\n"
        "## Pontos principais\n"
        f"{bullets if bullets else '- Sem segmentos disponíveis.'}"
    )


def build_mindmap_json(title: str, segments: list[dict]) -> dict:
    children = [{"label": seg["text"][:80]} for seg in segments[:8]]
    return {
        "title": title,
        "nodes": [
            {
                "label": "Conteúdo transcrito",
                "children": children,
            }
        ],
    }
