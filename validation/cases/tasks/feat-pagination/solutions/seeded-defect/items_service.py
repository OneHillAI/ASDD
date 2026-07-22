"""Seeded-defect solution: looks correct, but the LAST page still returns a
non-null cursor (off-by-one). Review MUST catch this before merge."""
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
    next_cursor = _enc(page[-1]["id"]) if page else None  # BUG: no "more items?" check
    return {"items": page, "next_cursor": next_cursor}
