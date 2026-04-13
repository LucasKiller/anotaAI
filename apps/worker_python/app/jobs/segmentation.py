def build_segments(full_text: str) -> list[dict]:
    chunks: list[str] = []
    sentences = [part.strip() for part in full_text.replace("\n", " ").split(".") if part.strip()]

    buffer = ""
    for sentence in sentences:
        piece = f"{sentence}."
        if len(buffer) + len(piece) > 180 and buffer:
            chunks.append(buffer.strip())
            buffer = piece
        else:
            buffer = f"{buffer} {piece}".strip()

    if buffer:
        chunks.append(buffer)

    segments: list[dict] = []
    for idx, chunk in enumerate(chunks):
        start_ms = idx * 30_000
        end_ms = start_ms + 30_000
        segments.append(
            {
                "segment_index": idx,
                "start_ms": start_ms,
                "end_ms": end_ms,
                "text": chunk,
                "tokens_estimate": max(1, len(chunk.split()) * 2),
            }
        )

    return segments
