#!/usr/bin/env python3
"""plan 摘要：只输出资源计数与顶层地址列表（不打印策略/变量值）。

用法: terraform show -json tfplan | python scripts/plan_summary.py
      python scripts/plan_summary.py plan.json
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path


def load(path: str | None) -> dict:
    if path and path != "-":
        return json.loads(Path(path).read_text(encoding="utf-8"))
    return json.load(sys.stdin)


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else None
    plan = load(path)
    changes = plan.get("resource_changes") or []

    counts: Counter[str] = Counter()
    addresses: list[tuple[str, str]] = []  # (action, address)

    for rc in changes:
        actions = (rc.get("change") or {}).get("actions") or []
        addr = rc.get("address") or rc.get("type", "?")
        if actions == ["no-op"]:
            counts["no-op"] += 1
            continue
        if actions == ["create"]:
            counts["create"] += 1
            addresses.append(("create", addr))
        elif actions == ["delete"]:
            counts["delete"] += 1
            addresses.append(("delete", addr))
        elif actions == ["update"]:
            counts["update"] += 1
            addresses.append(("update", addr))
        elif set(actions) == {"create", "delete"}:
            counts["replace"] += 1
            addresses.append(("replace", addr))
        else:
            counts["other"] += 1
            addresses.append(("other", addr))

    print("<!-- cloudjian-tf-plan-summary -->")
    print(
        f"- **create** {counts['create']} · **update** {counts['update']} · "
        f"**replace** {counts['replace']} · **delete** {counts['delete']} · "
        f"**no-op** {counts['no-op']}"
    )
    print()
    if addresses:
        print("| action | address |")
        print("|---|---|")
        for action, addr in sorted(addresses, key=lambda x: (x[0], x[1])):
            # 地址不含敏感值；仍避免打印 module 内 policy 全文
            print(f"| {action} | `{addr}` |")
    else:
        print("_No changes._")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
