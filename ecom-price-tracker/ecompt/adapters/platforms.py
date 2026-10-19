"""真实平台适配器（京东 / 淘宝 / 拼多多）。

合规与实现边界（重要）
----------------------
1. 京东、淘宝、拼多多的**网页端不允许自动化抓取**：服务条款明确禁止，
   且存在滑块/登录墙/风控指纹等反爬机制。因此本模块**不提供任何绕过手段**，
   只实现「走官方开放平台 / 已授权数据源」的配置化 JSON API 适配器。
2. 使用方式：在 config/sources.json 里填好你自己已获批的应用信息
   （endpoint / 请求参数 / 响应字段映射），并把凭证放进环境变量。
3. 凭证缺失或未启用时，适配器会抛 AdapterUnavailable，pipeline 会
   在「采集报告」里输出「跳过 + 原因」，不影响其他数据源聚合。
4. 若目标是自建/授权的数据服务（如聚合数据、店查查等），
   只要它返回 JSON，配置好字段映射即可直接复用本适配器。

扩展 JS 渲染页面（如内网/自建商城）
-----------------------------------
若目标站点是 JS 渲染且你有权访问，可安装 playwright 后继承本类，
覆写 _request() 用浏览器上下文取回渲染后的 HTML，再走同一套归一化流程。
"""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import AdapterError, AdapterUnavailable, BaseAdapter, RateLimiter, dig, http_get, http_post_json

CONFIG_PATH = Path(__file__).resolve().parents[2] / "config" / "sources.json"

# 各平台官方开放平台的默认配置骨架（可被 config/sources.json 覆盖）
DEFAULT_SOURCES: Dict[str, Dict[str, Any]] = {
    "京东": {
        "enabled": False,
        "mode": "api",
        "note": "京东开放平台/京东联盟：需申请 app_key + app_secret，请求需按平台规则签名",
        "endpoint": "https://api.jd.com/routerjson",
        "method": "POST",
        "api_key_env": "JD_API_KEY",
        "params": {"method": "jd.union.open.goods.query",
                   "keyword": "{keyword}", "pageSize": "{limit}"},
        "list_path": "jd_union_open_goods_query_response.result.data",
        "fields": {"id": "skuId", "title": "skuName", "price": "priceInfo.price",
                   "sales": "inOrderCount30Days", "shop": "shopInfo.shopName",
                   "rating": "shopInfo.shopLevel", "url": "materialUrl"},
    },
    "淘宝": {
        "enabled": False,
        "mode": "api",
        "note": "淘宝开放平台：需申请 AppKey/AppSecret，需签名，且需具备商品接口权限",
        "endpoint": "https://eco.taobao.com/router/rest",
        "method": "GET",
        "api_key_env": "TB_APP_KEY",
        "params": {"method": "taobao.tbk.dg.material.optional", "q": "{keyword}",
                   "page_size": "{limit}", "sign_method": "md5"},
        "list_path": "tbk_dg_material_optional_response.result_list.map_data",
        "fields": {"id": "item_id", "title": "title", "price": "zk_final_price",
                   "original_price": "reserve_price", "sales": "volume",
                   "shop": "shop_title", "rating": "seller_rating", "url": "url"},
    },
    "拼多多": {
        "enabled": False,
        "mode": "api",
        "note": "拼多多开放平台：需申请 client_id/client_secret 并签名",
        "endpoint": "https://gw-api.pinduoduo.com/api/router",
        "method": "POST",
        "api_key_env": "PDD_CLIENT_ID",
        "params": {"type": "pdd.ddk.goods.search", "keyword": "{keyword}",
                   "page_size": "{limit}", "data_type": "JSON"},
        "list_path": "goods_search_response.goods_list",
        "fields": {"id": "goods_id", "title": "goods_name", "price": "min_group_price",
                   "sales": "sales_tip", "shop": "mall_name", "url": "goods_url"},
    },
}


def load_sources_config() -> Dict[str, Any]:
    """读取用户配置，与默认骨架做深合并。"""
    merged = json.loads(json.dumps(DEFAULT_SOURCES))
    if CONFIG_PATH.exists():
        try:
            user_cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise AdapterError(f"config/sources.json 解析失败: {exc}") from exc
        for name, entry in (user_cfg.get("sources") or {}).items():
            merged.setdefault(name, {}).update(entry)
    return merged


class OfficialApiAdapter(BaseAdapter):
    """配置驱动的 JSON API 适配器：请求模板 + 响应字段映射。"""

    name = "official-api"
    _limiter = RateLimiter(qps=2.0)

    def __init__(self, platform: str):
        self.platform = platform
        self.cfg = load_sources_config().get(platform, {})

    # ---- 可用性判定 ----
    def credential(self) -> str:
        env_name = self.cfg.get("api_key_env", "")
        return os.environ.get(env_name, "") if env_name else ""

    def available(self) -> Optional[str]:
        if not self.cfg:
            return "config/sources.json 中未找到该平台配置"
        if not self.cfg.get("enabled"):
            return f"未启用（{self.cfg.get('note', '需在 config/sources.json 中 enabled=true')}）"
        env_name = self.cfg.get("api_key_env", "")
        if env_name and not self.credential():
            return f"缺少凭证：环境变量 {env_name} 未设置"
        if not self.cfg.get("endpoint"):
            return "未配置 endpoint"
        return None

    # ---- 采集 ----
    def _render(self, value: Any, keyword: str, limit: int) -> Any:
        if isinstance(value, str):
            return value.replace("{keyword}", keyword).replace("{limit}", str(limit))
        if isinstance(value, dict):
            return {k: self._render(v, keyword, limit) for k, v in value.items()}
        if isinstance(value, list):
            return [self._render(v, keyword, limit) for v in value]
        return value

    def _request(self, keyword: str, limit: int) -> str:
        params = self._render(self.cfg.get("params", {}), keyword, limit)
        headers = dict(self.cfg.get("headers", {}))
        key_env = self.cfg.get("api_key_env", "")
        if key_env and self.credential():
            # 不同平台的凭证放置位置不同（query / header / 签名），
            # 这里按配置的 credential_in 决定，默认放在 header。
            where = self.cfg.get("credential_in", "header")
            if where == "query":
                params.setdefault("apikey", self.credential())
            else:
                headers.setdefault("Authorization", f"Bearer {self.credential()}")
        timeout = float(self.cfg.get("timeout", 8.0))
        if str(self.cfg.get("method", "GET")).upper() == "POST":
            return http_post_json(self.cfg["endpoint"], params, headers=headers,
                                  timeout=timeout, limiter=self._limiter)
        return http_get(self.cfg["endpoint"], params=params, headers=headers,
                        timeout=timeout, limiter=self._limiter)

    def fetch(self, keyword: str, limit: int = 60) -> List[Dict[str, Any]]:
        reason = self.available()
        if reason:
            raise AdapterUnavailable(self.platform, reason)

        text = self._request(keyword, limit)
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as exc:
            raise AdapterError(f"[{self.platform}] 响应不是合法 JSON：{text[:200]}") from exc

        items = dig(payload, self.cfg.get("list_path", ""), default=[])
        if isinstance(items, dict):            # 有些接口返回 {"list": [...]}
            items = dig(items, "list", default=[])
        if not isinstance(items, list):
            raise AdapterError(f"[{self.platform}] list_path 未命中列表，请检查字段映射")

        mapping = self.cfg.get("fields", {})
        rows: List[Dict[str, Any]] = []
        for item in items[:limit]:
            if not isinstance(item, dict):
                continue
            row = {key: dig(item, path) for key, path in mapping.items()}
            row["platform"] = self.platform
            row["extra"] = {"raw_brand": dig(item, mapping.get("brand", "")) if mapping.get("brand") else None}
            rows.append(row)
        return rows


class JDAdapter(OfficialApiAdapter):
    def __init__(self):
        super().__init__("京东")


class TaobaoAdapter(OfficialApiAdapter):
    def __init__(self):
        super().__init__("淘宝")


class PddAdapter(OfficialApiAdapter):
    def __init__(self):
        super().__init__("拼多多")
