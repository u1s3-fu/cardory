"""采集适配器注册表。"""

from __future__ import annotations

from typing import Dict, List

from .base import AdapterError, AdapterUnavailable, BaseAdapter
from .demo import DemoAdapter
from .platforms import JDAdapter, PddAdapter, TaobaoAdapter

DEMO_PLATFORMS: List[str] = ["京东", "淘宝", "拼多多"]

LIVE_ADAPTERS: Dict[str, type] = {
    "京东": JDAdapter,
    "淘宝": TaobaoAdapter,
    "拼多多": PddAdapter,
}


def build_adapters(platforms: List[str] | None = None, source: str = "demo") -> List[BaseAdapter]:
    """按 source 与平台列表构建适配器。

    source="demo"：单例仿真适配器，覆盖全部所选平台（开箱即跑）
    source="live"：按平台实例化官方 API 适配器，凭证缺失时由 pipeline 记录跳过原因
    """
    platforms = platforms or list(DEMO_PLATFORMS)
    if source == "demo":
        return [DemoAdapter(platforms=platforms)]
    adapters: List[BaseAdapter] = []
    for name in platforms:
        cls = LIVE_ADAPTERS.get(name)
        if cls is None:
            continue
        adapters.append(cls())
    if not adapters:
        raise AdapterError(f"未识别的平台：{platforms}；可选 {list(LIVE_ADAPTERS)}")
    return adapters


__all__ = [
    "AdapterError", "AdapterUnavailable", "BaseAdapter",
    "DemoAdapter", "JDAdapter", "TaobaoAdapter", "PddAdapter",
    "build_adapters", "DEMO_PLATFORMS", "LIVE_ADAPTERS",
]
