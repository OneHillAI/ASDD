"""Independent acceptance oracle for the pagination task. Scores any candidate
`items_service` module. Deliberately separate from whatever built the change."""


def run(svc):
    checks = []

    def chk(name, cond, detail=""):
        checks.append((name, bool(cond), detail))

    r = svc.list_items(page_size=20)
    chk("first_page_size", len(r["items"]) == 20 and r["next_cursor"] is not None,
        f'len={len(r["items"])} cursor_set={r["next_cursor"] is not None}')

    pages, cur, guard = [], None, 0
    while True:
        r = svc.list_items(page_size=20, cursor=cur)
        pages.append(r)
        guard += 1
        if r["next_cursor"] is None or guard > 1000:
            break
        cur = r["next_cursor"]
    seen = [it["id"] for p in pages for it in p["items"]]
    chk("pages_disjoint_ordered", seen == list(range(1, 251)),
        f'collected={len(seen)}')

    nonempty = [p for p in pages if p["items"]]
    chk("last_page_cursor_null", bool(nonempty) and nonempty[-1]["next_cursor"] is None,
        f'last_nonempty_cursor_set={bool(nonempty) and nonempty[-1]["next_cursor"] is not None}')

    big = svc.list_items(page_size=200)
    dflt = svc.list_items()
    chk("clamp_and_default", len(big["items"]) == 100 and len(dflt["items"]) == 20,
        f'clamped={len(big["items"])} default={len(dflt["items"])}')

    r = svc.list_items(page_size=5)
    chk("items_shape", all({"id", "name"} <= set(it) for it in r["items"]), "")
    return checks
