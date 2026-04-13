def build_embeddings_stub(segments: list[dict]) -> list[dict]:
    """Stub para manter o ponto de extensão de embeddings locais."""
    return [{"segment_index": seg["segment_index"], "model_name": "local-stub"} for seg in segments]
