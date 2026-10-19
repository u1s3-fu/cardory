"""数据清洗层：脏值解析 → 字段归一化 → 去重 → 异常剔除 → 价格升序排序。

清洗规则（全部可解释、可回溯）
----------------------------
1. 脏值解析：价格兼容 ¥ / 券后 / 千分位 / 「19.9元起」/ 区间取低；
   销量兼容「已售 1.2万+」「月销 300」「3200+」；评分兼容 4.8 / 4.8分 / 98%。
2. 无效丢弃：价格无法解析、≤0，或超过 20 万元（明显不是商品到手价的脏数据）。
3. 去重：同一 platform+shop 下，分组键相同或标题相似度 ≥0.82 视为重复，
   保留价格更低的一条（同一商品在同一店铺的重复铺货）。
   —— 注意：**跨平台同款不去重**，这正是横向比价的价值所在。
4. 异常剔除：对 log(价格) 做 IQR 检验（下界 Q1-2·IQR，上界 Q3+2·IQR），
   命中者标为异常并从排名中剔除，但保留在结果里供人工复核。
5. 排序：清洗后的商品按价格升序编号。
"""

from __future__ import annotations

import datetime as dt
import hashlib
import math
import re
from dataclasses import dataclass, field
from statistics import median
from typing import Any, Dict, List, Optional, Tuple

from .models import Product

# ---------------------------------------------------------------- 脏值解析

_NUM = re.compile(r"\d+(?:\.\d+)?")
_TITLE_NOISE = [
    "包邮", "正品保证", "官方正品", "官方旗舰店", "旗舰店", "自营", "厂家直销",
    "限时特价", "限时", "特价", "秒杀", "新品", "爆款", "热卖", "顺丰", "现货",
    "正品", "官方", "全网最低", "买一送一",
]
_STRIP_CHARS = re.compile(r"[\s\-_/·•,，.。:：;；!！?？\"'“”‘’()（）\[\]【】<>《》|+]+")


def parse_price(value: Any) -> Optional[float]:
    """把任意格式的价格文本解析为 float（元）。"""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        price = float(value)
    else:
        text = str(value).strip().replace(",", "").replace("，", "")
        if not text:
            return None
        nums = _NUM.findall(text)
        if not nums:
            return None
        price = float(nums[0])           # 区间价「19.9-29.9」取低值
        if "万" in text:
            price *= 10000
    if not math.isfinite(price) or price <= 0:
        return None
    return round(price, 2)


def parse_int(value: Any) -> int:
    """把「1.2万+」「已售 300」「3200」等解析为 int。"""
    if value is None or isinstance(value, bool):
        return 0
    if isinstance(value, (int, float)):
        return int(value) if math.isfinite(float(value)) else 0
    match = _NUM.search(str(value).replace(",", ""))
    if not match:
        return 0
    num = float(match.group(0))
    tail = str(value)[match.end():match.end() + 1]
    if tail == "万" or "万" in str(value)[:match.end() + 2]:
        num *= 10000
    elif tail in ("千", "k", "K"):
        num *= 1000
    elif tail in ("亿",):
        num *= 100000000
    return int(num)


def parse_rating(value: Any) -> float:
    """评分归一化到 0~5。百分制（98）或百分好评率会按 /20 折算。"""
    if value is None or isinstance(value, bool):
        return 0.0
    if isinstance(value, (int, float)):
        rating = float(value)
    else:
        match = _NUM.search(str(value))
        if not match:
            return 0.0
        rating = float(match.group(0))
    if rating > 5:
        rating = 5.0 if rating >= 95 else rating / 20
    return round(min(max(rating, 0.0), 5.0), 1)


def tidy_title(title: Any) -> str:
    """去促销词、压空白、去首尾符号。"""
    text = re.sub(r"<[^>]+>", " ", str(title or ""))
    text = text.replace("【", " ").replace("】", " ").replace("[", " ").replace("]", " ")
    for word in _TITLE_NOISE:
        text = text.replace(word, " ")
    return re.sub(r"\s+", " ", text).strip(" -_·•|") or "未命名商品"


def normalize_key(text: str) -> str:
    return _STRIP_CHARS.sub("", str(text).lower())


def tokens(text: str) -> set:
    return set(re.findall(r"[a-z0-9]+|[\u4e00-\u9fff]{2,}", normalize_key(text)))


def jaccard(a: str, b: str) -> float:
    ta, tb = tokens(a), tokens(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def make_group_key(title: str, extra: Dict[str, Any] | None = None) -> Tuple[str, str]:
    """同款分组键：优先用结构化型号字段；否则退化为标题前 12 字的指纹。"""
    model = (extra or {}).get("model")
    if model:
        return normalize_key(str(model)), str(model)
    return normalize_key(title)[:12], title[:24]


# ---------------------------------------------------------------- 清洗流水线

@dataclass
class CleanStats:
    raw_count: int = 0
    valid_count: int = 0
    invalid_dropped: int = 0
    duplicates_removed: int = 0
    outliers_removed: int = 0

    def to_dict(self) -> Dict[str, int]:
        return {
            "raw_count": self.raw_count,
            "valid_count": self.valid_count,
            "invalid_dropped": self.invalid_dropped,
            "duplicates_removed": self.duplicates_removed,
            "outliers_removed": self.outliers_removed,
        }


@dataclass
class CleanResult:
    products: List[Product] = field(default_factory=list)
    outliers: List[Product] = field(default_factory=list)
    removed_duplicates: List[Dict[str, Any]] = field(default_factory=list)
    stats: CleanStats = field(default_factory=CleanStats)


MAX_PRICE = 200_000.0
OUTLIER_IQR_FACTOR = 2.0
TITLE_SIM_THRESHOLD = 0.82


def clean(rows: List[Dict[str, Any]], keyword: str = "") -> CleanResult:
    stats = CleanStats(raw_count=len(rows))
    captured = dt.datetime.now().replace(microsecond=0).isoformat()
    result_dups: List[Dict[str, Any]] = []

    # 1) 解析 + 归一化
    parsed: List[Product] = []
    for row in rows:
        price = parse_price(row.get("price"))
        if price is None or price > MAX_PRICE:
            stats.invalid_dropped += 1
            continue
        title = tidy_title(row.get("title"))
        group_key, group_label = make_group_key(title, row.get("extra"))
        raw_id = str(row.get("id") or "") or f"{row.get('platform')}|{title}|{price}"
        parsed.append(Product(
            id=hashlib.md5(raw_id.encode("utf-8")).hexdigest()[:12],
            platform=str(row.get("platform") or "未知"),
            title=title,
            price=price,
            keyword=keyword,
            sales=parse_int(row.get("sales")),
            comments=parse_int(row.get("comments")),
            shop=tidy_title(row.get("shop")),
            shop_rating=parse_rating(row.get("shop_rating")),
            url=str(row.get("url") or ""),
            original_price=parse_price(row.get("original_price")),
            group_key=group_key,
            group_label=group_label,
            captured_at=str(row.get("captured_at") or captured),
            extra={k: v for k, v in (row.get("extra") or {}).items() if k != "model"},
        ))

    # 2) 去重：同 platform + 同 shop 内，同分组键或标题高度相似 → 保留更低价
    #    先按价格升序，天然保证「保留更便宜的那条」
    kept: List[Product] = []
    seen_url: Dict[str, Product] = {}
    for item in sorted(parsed, key=lambda p: p.price):
        if item.url and item.url in seen_url:
            stats.duplicates_removed += 1
            result_dups.append({
                "platform": item.platform, "title": item.title, "price": item.price,
                "kept_title": seen_url[item.url].title, "kept_price": seen_url[item.url].price,
                "reason": "链接重复",
            })
            continue
        duplicate = None
        for exist in kept:
            if exist.platform != item.platform or exist.shop != item.shop:
                continue
            if exist.group_key == item.group_key or jaccard(exist.title, item.title) >= TITLE_SIM_THRESHOLD:
                duplicate = exist
                break
        if duplicate is not None:
            stats.duplicates_removed += 1
            result_dups.append({
                "platform": item.platform, "title": item.title, "price": item.price,
                "kept_title": duplicate.title, "kept_price": duplicate.price,
                "reason": "同店同款重复铺货",
            })
            continue
        seen_url[item.url] = item
        kept.append(item)

    # 3) 异常剔除（log 价格的 IQR 检验，样本过少时跳过）
    valid: List[Product] = []
    outliers: List[Product] = []
    if len(kept) >= 8:
        logs = sorted(math.log(p.price) for p in kept)
        q1 = logs[len(logs) // 4]
        q3 = logs[(len(logs) * 3) // 4]
        iqr = q3 - q1
        lo, hi = math.exp(q1 - OUTLIER_IQR_FACTOR * iqr), math.exp(q3 + OUTLIER_IQR_FACTOR * iqr)
    else:
        lo, hi = 0.0, float("inf")
    for item in kept:
        if item.price < lo or item.price > hi:
            outliers.append(item)
        else:
            valid.append(item)

    # 4) 价格升序 + 排名
    valid.sort(key=lambda p: (p.price, -p.sales))
    for idx, item in enumerate(valid, start=1):
        item.rank = idx

    stats.valid_count = len(valid)
    stats.outliers_removed = len(outliers)
    for item in outliers:
        item.tags.append("价格异常")
        item.extra["outlier_reason"] = f"价格 {item.price} 落在合理区间 [{round(lo, 2)}, {round(hi, 2)}] 之外"

    return CleanResult(products=valid, outliers=outliers,
                       removed_duplicates=result_dups, stats=stats)


# ---------------------------------------------------------------- 统计辅助

def price_stats(prices: List[float]) -> Dict[str, float]:
    if not prices:
        return {"min": 0.0, "max": 0.0, "avg": 0.0, "median": 0.0, "total": 0.0}
    return {
        "min": round(min(prices), 2),
        "max": round(max(prices), 2),
        "avg": round(sum(prices) / len(prices), 2),
        "median": round(median(prices), 2),
        "total": round(sum(prices), 2),
    }
