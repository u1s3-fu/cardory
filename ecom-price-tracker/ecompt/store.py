"""价格历史存储：把每次采集落盘为快照，驱动价格趋势图。

快照结构（data/history.json）
    {
      "无线蓝牙耳机": {
        "snapshots": [
          {"date": "2026-10-19", "platforms": {"京东": 1234.5, ...},
           "all_avg": 1100.2, "best_price": 899.0, "best_title": "...",
           "count": 38, "synthetic": false}
        ]
      }
    }

- 同一关键词、同一天只保留一条快照（重复运行会覆盖，便于反复演示）。
- demo 模式下若历史不足，会用确定性随机游走**回溯生成**若干天合成快照，
  让趋势图在首次运行时就可用；这些点会标记 synthetic=true 并在图上注明。
"""

from __future__ import annotations

import datetime as dt
import json
import random
import zlib
from pathlib import Path
from typing import Any, Dict, List, Optional

from .models import Product

DEFAULT_PATH = Path(__file__).resolve().parents[1] / "data" / "history.json"


class HistoryStore:
    def __init__(self, path: Optional[Path | str] = None):
        self.path = Path(path) if path else DEFAULT_PATH
        self._data: Dict[str, Any] = {}
        if self.path.exists():
            try:
                self._data = json.loads(self.path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                self._data = {}

    # ---------------- 基础读写
    def snapshots(self, keyword: str) -> List[Dict[str, Any]]:
        entry = self._data.get(keyword) or {}
        snaps = entry.get("snapshots") or []
        return sorted(snaps, key=lambda s: s.get("date", ""))

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self._data, ensure_ascii=False, indent=2), encoding="utf-8")

    def append(self, keyword: str, record: Dict[str, Any]) -> None:
        entry = self._data.setdefault(keyword, {"snapshots": []})
        snaps = [s for s in entry["snapshots"] if s.get("date") != record["date"]]
        snaps.append(record)
        entry["snapshots"] = sorted(snaps, key=lambda s: s["date"])
        self.save()

    # ---------------- 记录当前采集
    def record_run(self, keyword: str, products: List[Product], synthetic: bool = False) -> Dict[str, Any]:
        platforms: Dict[str, float] = {}
        for item in products:
            platforms.setdefault(item.platform, [])
            platforms[item.platform].append(item.price)
        platforms = {k: round(sum(v) / len(v), 2) for k, v in platforms.items() if v}
        cheapest = min(products, key=lambda p: p.price) if products else None
        record = {
            "date": dt.date.today().isoformat(),
            "platforms": platforms,
            "all_avg": round(sum(p.price for p in products) / len(products), 2) if products else 0,
            "best_price": cheapest.price if cheapest else 0,
            "best_title": cheapest.title if cheapest else "",
            "count": len(products),
            "synthetic": synthetic,
        }
        self.append(keyword, record)
        return record

    # ---------------- demo 模式：回溯生成历史
    def seed_demo(self, keyword: str, products: List[Product], days: int = 6) -> bool:
        if not products:
            return False
        existing = {s["date"] for s in self.snapshots(keyword)}
        if len(existing) > 2:
            return False

        rng = random.Random(zlib.crc32(f"hist-{keyword}".encode("utf-8")))
        platforms: Dict[str, List[float]] = {}
        for item in products:
            platforms.setdefault(item.platform, []).append(item.price)
        base = {k: sum(v) / len(v) for k, v in platforms.items()}
        base_all = sum(base.values()) / len(base)
        base_best = min(p.price for p in products)
        best_title = min(products, key=lambda p: p.price).title

        today = dt.date.today()
        state = dict(base)
        created = False
        for back in range(days, 0, -1):
            day = (today - dt.timedelta(days=back)).isoformat()
            if day in existing:
                continue
            # 向过去回溯时价格缓慢上浮（促销周期），并叠加小幅噪声
            for key in state:
                state[key] = state[key] * (1 + rng.uniform(0.006, 0.03))
            drift = 1 + 0.012 * back + rng.uniform(-0.01, 0.01)
            self.append(keyword, {
                "date": day,
                "platforms": {k: round(v, 2) for k, v in state.items()},
                "all_avg": round(base_all * drift, 2),
                "best_price": round(base_best * (1 + 0.015 * back + rng.uniform(0, 0.01)), 2),
                "best_title": best_title,
                "count": len(products),
                "synthetic": True,
            })
            created = True
        return created

    # ---------------- 趋势数据
    def trend(self, keyword: str, product_platforms: Optional[List[str]] = None) -> Dict[str, Any]:
        snaps = self.snapshots(keyword)
        dates = [s["date"] for s in snaps]
        platforms: List[str] = []
        for snap in snaps:
            for plat in (snap.get("platforms") or {}):
                if plat not in platforms:
                    platforms.append(plat)
        if product_platforms:
            platforms = [p for p in platforms if p in product_platforms] or platforms

        series: List[Dict[str, Any]] = []
        for plat in platforms:
            points = [{"date": d, "value": (snap.get("platforms") or {}).get(plat)}
                      for d, snap in zip(dates, snaps)]
            points = [p for p in points if p["value"] is not None]
            if points:
                series.append({"name": plat, "kind": "platform", "points": points})
        best_points = [{"date": s["date"], "value": s.get("best_price")} for s in snaps if s.get("best_price")]
        if best_points:
            series.append({"name": "全场最低价", "kind": "best", "points": best_points})

        return {
            "keyword": keyword,
            "dates": dates,
            "series": series,
            "synthetic": any(s.get("synthetic") for s in snaps),
            "snapshot_count": len(snaps),
            "latest": snaps[-1] if snaps else None,
        }
