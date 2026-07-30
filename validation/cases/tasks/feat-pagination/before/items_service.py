"""Fake sandbox app: an items listing service. BEFORE state (no pagination).
The ASDD loop is asked to add pagination per ../spec.md; this is the starting tree."""
ITEMS = [{"id": i, "name": f"item-{i}"} for i in range(1, 251)]  # 250 items


def list_items(page_size=20, cursor=None):
    # No pagination yet: returns everything, ignores page_size/cursor.
    return {"items": list(ITEMS), "next_cursor": None}
