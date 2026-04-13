def update_chat_index_stub(recording_id: str) -> dict:
    """Mantém contrato explícito para futura indexação híbrida lexical + vetorial."""
    return {"recording_id": recording_id, "status": "indexed_stub"}
