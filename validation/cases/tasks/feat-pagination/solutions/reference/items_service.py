"""Reference solution: correct cursor pagination (the known-good target)."""
import base64
ITEMS = [{"id": i, "name": f"item-{i}"} for i in range(1, 251)]


def _enc(n):
    return base64.urlsafe_b64encode(str(n).encode()).decode()


def _dec(c):
    return int(base64.urlsafe_b64decode(c.encode()).decode())


def list_items(page_size=20, cursor=None):
    page_size = 20 if page_size is None else max(1, min(int(page_size), 100))
    start = 0
    if cursor is not None:
        last_id = _dec(cursor)
        start = next((i for i, it in enumerate(ITEMS) if it["id"] > last_id), len(ITEMS))
    page = ITEMS[start:start + page_size]
    end = start + len(page)
    next_cursor = _enc(page[-1]["id"]) if (end < len(ITEMS) and page) else None
    return {"items": page, "next_cursor": next_cursor}
