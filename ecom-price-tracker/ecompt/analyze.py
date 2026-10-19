"""分析层：统计概览、跨平台同款横向对比、性价比评分与推荐标注。

性价比指数（0~100）采用「秩百分位」而非 min-max 归一化，
对长尾价格/销量分布更稳健（异常值已在清洗层剔除）：

    指数 = 100 × (0.5 × 价格得分 + 0.3 × 销量得分 + 0.2 × 评分得分)

其中价格得分是「越便宜越高」，销量/评分同理；跨平台同款组内最低价额外打标。
"""

from __future__ import annotations

from collections import defaultdict
from typing import Any, Callable, Dict, List, Optional

from .clean import price_stats
from .models import Product

W_PRICE, W_SALES, W_RATING = 0.5, 0.3, 0.2


def _rank01(products: List[Product], key: Callable[[Product], float],
            lower_is_better: bool = False) -> Dict[str, float]:
    """秩百分位：返回 {product.id: 0~1}，1 表示该指标最优。"""
    n = len(products)
    if n == 0:
        return {}
    if n == 1:
        return {products[0].id: 1.0}
    order = sorted(range(n), key=lambda i: key(products[i]))
    out: Dict[str, float] = {}
    for pos, i in enumerate(order):
        pct = pos / (n - 1)
        out[products[i].id] = 1 - pct if lower_is_better else pct
    return out


def score_products(products: List[Product]) -> None:
    """就地写入 product.score / product.tags（价格优势、销量之星等）。"""
    if not products:
        return
    price_score = _rank01(products, lambda p: p.price, lower_is_better=True)
    sales_score = _rank01(products, lambda p: p.sales)
    rating_score = _rank01(products, lambda p: (p.shop_rating, p.sales))

    for item in products:
        item.score = round(100 * (
            W_PRICE * price_score.get(item.id, 0)
            + W_SALES * sales_score.get(item.id, 0)
            + W_RATING * rating_score.get(item.id, 0)
        ), 1)

    cheapest = min(products, key=lambda p: p.price)
    cheapest.tags.append("全场最低价")
    best_sales = max(products, key=lambda p: p.sales)
    best_sales.tags.append("销量之星")
    best_rating = max(products, key=lambda p: (p.shop_rating, p.sales))
    best_rating.tags.append("口碑之星")
    for item in products:
        if item.original_price and item.discount >= 0.15:
            item.tags.append(f"折扣 {round(item.discount * 100)}%")


def platform_stats(products: List[Product]) -> List[Dict[str, Any]]:
    """各平台价格水位与销量分布，用于横向对比的第一层结论。"""
    buckets: Dict[str, List[Product]] = defaultdict(list)
    for item in products:
        buckets[item.platform].append(item)

    all_avg = (sum(p.price for p in products) / len(products)) if products else 0
    rows: List[Dict[str, Any]] = []
    for platform, items in buckets.items():
        stats = price_stats([p.price for p in items])
        rows.append({
            "platform": platform,
            "count": len(items),
            "min_price": stats["min"],
            "avg_price": stats["avg"],
            "median_price": stats["median"],
            "max_price": stats["max"],
            "total_sales": sum(p.sales for p in items),
            "avg_rating": round(sum(p.shop_rating for p in items) / len(items), 2),
            "price_index": round(stats["avg"] / all_avg, 3) if all_avg else 1.0,
        })
    rows.sort(key=lambda r: r["avg_price"])
    return rows


def build_groups(products: List[Product]) -> List[Dict[str, Any]]:
    """构建跨平台同款分组（横向对比的核心数据结构）。"""
    buckets: Dict[str, List[Product]] = defaultdict(list)
    for item in products:
        buckets[item.group_key].append(item)

    groups: List[Dict[str, Any]] = []
    for key, items in buckets.items():
        # 同款同平台可能有多店，取该平台最低价作为该平台代表
        per_platform: Dict[str, Product] = {}
        for it in items:
            cur = per_platform.get(it.platform)
            if cur is None or it.price < cur.price:
                per_platform[it.platform] = it
        prices = [p.price for p in per_platform.values()]
        lo, hi = min(prices), max(prices)
        best_platform = min(per_platform.items(), key=lambda kv: kv[1].price)[0]
        avg = sum(prices) / len(prices)
        group = {
            "key": key,
            "label": items[0].group_label,
            "platform_count": len(per_platform),
            "platforms": {
                plat: {
                    "id": p.id, "title": p.title, "price": p.price, "sales": p.sales,
                    "shop": p.shop, "shop_rating": p.shop_rating, "url": p.url,
                    "original_price": p.original_price,
                }
                for plat, p in per_platform.items()
            },
            "best_platform": best_platform,
            "best_price": lo,
            "max_price": hi,
            "avg_price": round(avg, 2),
            "spread_pct": round((hi - lo) / avg * 100, 1) if avg else 0.0,
            "saving_pct": round((hi - lo) / hi * 100, 1) if hi else 0.0,
            "saving_amount": round(hi - lo, 2),
            "sales_total": sum(p.sales for p in items),
            "shop_count": len(items),
        }
        # 回写分组信息到商品（用于表格展示与打标）
        for plat, p in per_platform.items():
            p.extra["group_platforms"] = sorted(per_platform)
            p.extra["group_best_platform"] = best_platform
            p.extra["group_best_price"] = lo
            p.extra["group_max_price"] = hi
            p.extra["group_saving_pct"] = group["saving_pct"]
            if len(per_platform) >= 2 and p.price == lo:
                p.tags.append("同款最低")
            elif len(per_platform) >= 2 and p.price == hi:
                p.tags.append("同款最高")
        groups.append(group)

    groups.sort(key=lambda g: (-g["platform_count"], -g["saving_pct"], g["best_price"]))
    return groups


def build_recommendations(products: List[Product],
                          groups: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """生成带解释的推荐标注（每条都说明「为什么推荐」）。"""
    recs: List[Dict[str, Any]] = []
    if not products:
        return recs

    def pack(tag: str, reason: str, product: Optional[Product] = None,
             group: Optional[Dict[str, Any]] = None, level: str = "info") -> Dict[str, Any]:
        return {
            "tag": tag, "reason": reason, "level": level,
            "product": product.to_dict() if product else None,
            "group": group,
        }

    best_value = max(products, key=lambda p: p.score)
    recs.append(pack(
        "性价比之王",
        f"综合性价比指数 {best_value.score}/100（价格 {best_value.price} 元 · "
        f"月销 {best_value.sales} · 店铺评分 {best_value.shop_rating}），"
        f"在「价格 / 销量 / 口碑」三维加权中排名第一。",
        product=best_value, level="primary",
    ))

    best_sales = max(products, key=lambda p: p.sales)
    recs.append(pack(
        "销量冠军",
        f"月销 {best_sales.sales} 件，为本次采集销量最高；高销量通常意味着成熟供应链与更稳的售后服务。",
        product=best_sales,
    ))

    rated = [p for p in products if p.shop_rating > 0]
    if rated:
        best_rating = max(rated, key=lambda p: (p.shop_rating, p.sales))
        recs.append(pack(
            "口碑最佳",
            f"店铺评分 {best_rating.shop_rating}（满分 5）且月销 {best_rating.sales} 件，评价基数足够可信。",
            product=best_rating,
        ))

    multi = [g for g in groups if g["platform_count"] >= 2]
    if multi:
        gap = max(multi, key=lambda g: (g["saving_pct"], g["platform_count"]))
        recs.append(pack(
            "跨平台价差最大",
            f"同款「{gap['label']}」在 {gap['platform_count']} 个平台有售，"
            f"最高 {gap['max_price']} 元 vs 最低 {gap['best_price']} 元，"
            f"选 {gap['best_platform']} 可省 {gap['saving_amount']} 元（{gap['saving_pct']}%）。",
            group=gap, level="primary",
        ))

    # 价格洼地：同款组内价格低于组均价 8% 且组内有 2+ 平台
    ditches: List[Dict[str, Any]] = []
    for g in multi:
        for plat, info in g["platforms"].items():
            ratio = info["price"] / g["avg_price"] if g["avg_price"] else 1
            if ratio <= 0.92:
                ditches.append({
                    "tag": "价格洼地",
                    "reason": f"「{g['label']}」在 {plat} 报价 {info['price']} 元，"
                              f"低于同款均价 {g['avg_price']} 元 {round((1 - ratio) * 100)}%。",
                    "level": "warn",
                    "product": None,
                    "group": None,
                    "platform": plat,
                    "price": info["price"],
                    "label": g["label"],
                    "url": info.get("url", ""),
                    "shop": info.get("shop", ""),
                })
    ditches.sort(key=lambda d: d["price"])
    recs.extend(ditches[:3])

    return recs


def summarize(products: List[Product], groups: List[Dict[str, Any]],
              stats: Dict[str, int], source: str, keyword: str) -> Dict[str, Any]:
    prices = [p.price for p in products]
    result: Dict[str, Any] = {
        "keyword": keyword,
        "source": source,
        "count": len(products),
        "platform_count": len({p.platform for p in products}),
        "platform_list": sorted({p.platform for p in products}),
        "price": price_stats(prices),
        "total_sales": sum(p.sales for p in products),
        "avg_rating": round(sum(p.shop_rating for p in products) / len(products), 2) if products else 0,
        "comparable_groups": len([g for g in groups if g["platform_count"] >= 2]),
        "cleaning": stats,
    }
    if products:
        best = products[0] if products[0].price <= min(prices) else min(products, key=lambda p: p.price)
        result["cheapest"] = {"title": best.title, "platform": best.platform,
                              "price": best.price, "url": best.url, "shop": best.shop}
        result["top_score"] = max(products, key=lambda p: p.score).to_dict()
    return result
