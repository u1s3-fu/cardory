"""采集适配器基类 + 通用 HTTP 客户端。

设计要点
--------
1. 适配器只负责「拿到脏数据」（raw rows），不做解析与清洗 —— 单一职责，
   新增平台时无需改动清洗/分析/展示层。
2. 统一使用标准库 urllib，零第三方依赖；内置超时、指数退避重试、
   全局限速（QPS）与浏览器 UA，避免给目标站点造成压力。
3. 采集失败不抛到主流程：以 AdapterUnavailable 表示「跳过 + 原因」，
   pipeline 会把它记录进采集报告，保证多源聚合时单点失败不影响整体。
"""

from __future__ import annotations

import gzip
import io
import json
import random
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional


DEFAULT_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36 EcomPriceTracker/1.0"
)


class AdapterError(Exception):
    """采集过程中的可恢复错误。"""


class AdapterUnavailable(AdapterError):
    """适配器不可用（未配置凭证 / 未启用 / 依赖缺失）。

    携带 platform 与 reason，便于在采集报告中向用户解释「为什么这一路没数据」。
    """

    def __init__(self, platform: str, reason: str):
        self.platform = platform
        self.reason = reason
        super().__init__(f"[{platform}] {reason}")


class RateLimiter:
    """最小间隔限速器，保证对同一站点的请求不超过 qps。"""

    def __init__(self, qps: float = 1.0):
        self.min_interval = 1.0 / max(qps, 0.05)
        self._last = 0.0

    def wait(self) -> None:
        delta = time.monotonic() - self._last
        if delta < self.min_interval:
            time.sleep(self.min_interval - delta)
        self._last = time.monotonic()


def http_get(
    url: str,
    params: Optional[Dict[str, Any]] = None,
    headers: Optional[Dict[str, str]] = None,
    timeout: float = 8.0,
    retries: int = 2,
    limiter: Optional[RateLimiter] = None,
) -> str:
    """带重试与限速的 GET，返回文本（自动解 gzip / deflate）。"""
    if params:
        url = f"{url}{'&' if '?' in url else '?'}{urllib.parse.urlencode(params)}"
    hdrs = {"User-Agent": DEFAULT_UA, "Accept-Encoding": "gzip, deflate"}
    hdrs.update(headers or {})

    last_err: Optional[Exception] = None
    for attempt in range(retries + 1):
        if limiter:
            limiter.wait()
        try:
            req = urllib.request.Request(url, headers=hdrs)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
                return raw.decode("utf-8", errors="replace")
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as exc:
            last_err = exc
            if attempt < retries:
                time.sleep((2 ** attempt) * 0.5 + random.random() * 0.2)
    raise AdapterError(f"请求失败 {url}: {last_err}")


def http_post_json(
    url: str,
    payload: Dict[str, Any],
    headers: Optional[Dict[str, str]] = None,
    timeout: float = 8.0,
    retries: int = 1,
    limiter: Optional[RateLimiter] = None,
) -> str:
    """带重试的 JSON POST。"""
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    hdrs = {"User-Agent": DEFAULT_UA, "Content-Type": "application/json"}
    hdrs.update(headers or {})

    last_err: Optional[Exception] = None
    for attempt in range(retries + 1):
        if limiter:
            limiter.wait()
        try:
            req = urllib.request.Request(url, data=body, headers=hdrs, method="POST")
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                if resp.headers.get("Content-Encoding") == "gzip":
                    raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read()
                return raw.decode("utf-8", errors="replace")
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as exc:
            last_err = exc
            if attempt < retries:
                time.sleep(0.3 * (attempt + 1))
    raise AdapterError(f"请求失败 {url}: {last_err}")


def dig(obj: Any, path: str, default: Any = None) -> Any:
    """按 "a.b[0].c" 形式取嵌套字段，取不到返回 default。"""
    if not path:
        return obj
    cur = obj
    for part in path.split("."):
        if cur is None:
            return default
        if "[" in part and part.endswith("]"):
            name, idx = part[:-1].split("[")
            idx = int(idx)
            cur = cur.get(name) if isinstance(cur, dict) else None
            if not isinstance(cur, list) or len(cur) <= idx:
                return default
            cur = cur[idx]
        else:
            if not isinstance(cur, dict):
                return default
            cur = cur.get(part)
    return default if cur is None else cur


class BaseAdapter:
    """采集适配器接口。"""

    name: str = "base"
    platform: str = "unknown"

    def fetch(self, keyword: str, limit: int = 60) -> List[Dict[str, Any]]:
        """返回 raw rows（脏数据）。字段自由，清洗层做归一化。"""
        raise NotImplementedError

    def available(self) -> Optional[str]:
        """不可用时返回原因字符串，可用返回 None。"""
        return None

    # 供 pipeline 记录本轮采集情况
    def describe(self) -> Dict[str, Any]:
        return {"platform": self.platform, "adapter": self.name}
