"""内置仿真数据源（Demo Adapter）。

作用
----
在没有平台开放平台凭证的情况下，让整套流水线「开箱即跑」：
它按关键词生成一批**结构真实、噪声真实**的脏数据（价格混入 ¥ / 券后 /
千分位、销量混入「1.2万+」、标题混入促销词、并故意埋入重复行与异常低价/高价），
用于完整验证清洗、去重、异常剔除、对比、趋势与推荐链路。

数据是确定性生成的（种子 = 关键词的 CRC32），同一关键词每次结果一致，
便于回归测试与演示复现。所有 URL 均为构造的演示链接，不指向真实商品。
"""

from __future__ import annotations

import datetime as dt
import random
import zlib
from typing import Any, Dict, List, Tuple

from .base import BaseAdapter

# (平台, 相对价格系数, 评分下限, 评分上限, 销量系数)
PLATFORM_PROFILES: List[Tuple[str, float, float, float, float]] = [
    ("京东", 1.00, 4.75, 5.00, 1.0),
    ("淘宝", 0.94, 4.60, 4.95, 1.25),
    ("拼多多", 0.86, 4.45, 4.90, 1.70),
]

CATEGORY_KEYWORDS: List[Tuple[str, List[str]]] = [
    ("audio", ["耳机", "耳麦", "音箱", "音响", "耳塞"]),
    ("phone", ["手机", "iphone", "平板"]),
    ("laptop", ["笔记本", "电脑", "轻薄本", "游戏本", "主机"]),
    ("peripheral", ["键盘", "鼠标", "显示器", "手柄", "硬盘", "u盘", "充电", "数据线"]),
    ("home", ["杯", "壶", "收纳", "枕", "被", "置物", "锅", "餐具", "毛巾", "纸巾"]),
]

# 品类 → (价格区间, 型号池[(品牌, 系列)])
CATEGORY_MODELS: Dict[str, Tuple[Tuple[int, int], List[Tuple[str, str]]]] = {
    "audio": ((89, 1899), [
        ("华为", "FreeBuds SE2"), ("小米", "Redmi Buds 5"), ("漫步者", "LolliPods Pro"),
        ("索尼", "WF-C500"), ("韶音", "OpenRun Pro"), ("OPPO", "Enco Air3"),
        ("声阔", "Life P3"), ("荣耀", "Earbuds X5"), ("倍思", "Bowie E9"),
        ("JBL", "Tune 130NC"), ("铁三角", "ATH-S220BT"), ("红米", "Buds 4 青春版"),
    ]),
    "phone": ((899, 7499), [
        ("小米", "14 Pro"), ("荣耀", "Magic6"), ("一加", "Ace 3"), ("vivo", "X100"),
        ("OPPO", "Find X7"), ("realme", "GT Neo6"), ("红米", "K70 Pro"), ("努比亚", "Z60 Ultra"),
    ]),
    "laptop": ((2499, 12999), [
        ("联想", "小新 Pro14"), ("华硕", "天选5"), ("戴尔", "灵越14"), ("惠普", "星Book 15"),
        ("机械革命", "极光X"), ("荣耀", "MagicBook X16"), ("小米", "Redmi Book 16"),
    ]),
    "peripheral": ((29, 899), [
        ("罗技", "G304"), ("雷蛇", "黑寡妇V3"), ("达尔优", "A87 Pro"), ("狼蛛", "F75"),
        ("洛斐", "小翘68"), ("航嘉", "曲面27寸"),
    ]),
    "home": ((19, 399), [
        ("京东京造", "深睡夏凉被"), ("网易严选", "抗菌毛巾"), ("小米", "保温杯"),
        ("摩登主妇", "收纳箱"), ("苏泊尔", "不粘锅"), ("富光", "大容量水壶"),
    ]),
    "default": ((39, 1299), [
        ("京东京造", "经典款"), ("网易严选", "旗舰款"), ("小米", "升级款"),
        ("得力", "专业款"), ("南极人", "基础款"), ("蕉内", "Air款"),
    ]),
}

TITLE_SUFFIX = ["", "", "", "官方正品", "新款", "顺丰包邮"]
SHOP_SUFFIX = {
    "京东": ["京东自营旗舰店", "京东官方旗舰店", "品牌授权专营店"],
    "淘宝": ["官方旗舰店", "天猫旗舰店", "C店精品店"],
    "拼多多": ["官方旗舰店", "百亿补贴店", "品质工厂店"],
}
DIRTY_WORDS = ["【官方旗舰店】", "【限时特价】", "包邮", "正品保证"]


def _pick_category(keyword: str) -> str:
    low = keyword.lower()
    for cat, words in CATEGORY_KEYWORDS:
        if any(w in low for w in words):
            return cat
    return "default"


def _fmt_price(rng: random.Random, value: float) -> Any:
    """把干净价格包装成电商常见的脏格式。"""
    style = rng.randint(0, 3)
    if style == 0:
        return round(value, 2)
    if style == 1:
        return f"¥{value:,.2f}"
    if style == 2:
        return f"券后 ¥{value:.2f}"
    return f"{value:.2f}元起"


def _fmt_sales(rng: random.Random, value: int) -> Any:
    style = rng.randint(0, 2)
    if style == 0:
        return value
    if style == 1:
        return f"已售 {value}+"
    return f"{value / 10000:.1f}万+" if value >= 10000 else f"月销 {value}"


def _fmt_rating(rng: random.Random, value: float) -> Any:
    style = rng.randint(0, 2)
    if style == 0:
        return round(value, 1)
    if style == 1:
        return f"{value:.1f}分"
    return f"{int(value * 20)}%"


class DemoAdapter(BaseAdapter):
    """仿真数据源：为指定平台集合生成脏数据。"""

    name = "demo-simulator"
    platform = "京东/淘宝/拼多多"
    synthetic = True

    def __init__(self, platforms: List[str] | None = None):
        names = [p[0] for p in PLATFORM_PROFILES]
        self.platforms = [p for p in (platforms or names) if p in names] or names

    def fetch(self, keyword: str, limit: int = 60) -> List[Dict[str, Any]]:
        rng = random.Random(zlib.crc32(keyword.encode("utf-8")))
        cat = _pick_category(keyword)
        (low, high), models = CATEGORY_MODELS[cat]
        captured = dt.datetime.now().replace(microsecond=0).isoformat()
        profiles = [p for p in PLATFORM_PROFILES if p[0] in self.platforms]

        rows: List[Dict[str, Any]] = []

        def add(platform: str, model: str, price: float, rating: float,
                sales: int, dirty: bool = False) -> None:
            brand = model.split(" ")[0] if " " in model else model
            shop = f"{brand}{rng.choice(SHOP_SUFFIX[platform])}"
            title = f"{model} {keyword}"
            if dirty:
                title = f"{rng.choice(DIRTY_WORDS)}{model} {keyword} {rng.choice(DIRTY_WORDS)}"
            else:
                suffix = rng.choice(TITLE_SUFFIX)
                title = f"{title} {suffix}".strip()
            goods_id = rng.randint(10 ** 9, 10 ** 10 - 1)
            url_map = {
                "京东": f"https://item.jd.com/{goods_id}.html",
                "淘宝": f"https://item.taobao.com/item.htm?id={goods_id}",
                "拼多多": f"https://mobile.yangkeduo.com/goods.html?goods_id={goods_id}",
            }
            original = round(price * rng.uniform(1.05, 1.38), 2) if rng.random() < 0.55 else None
            rows.append({
                "platform": platform,
                "title": title,
                "price": _fmt_price(rng, price),
                "original_price": original,
                "sales": _fmt_sales(rng, sales),
                "comments": int(sales * rng.uniform(1.8, 5.5)),
                "shop": shop,
                "shop_rating": _fmt_rating(rng, rating),
                "url": url_map[platform],
                "captured_at": captured,
                "extra": {"model": model, "category": cat, "synthetic": True},
            })

        # 1) 主力型号：随机落在 2~3 个平台，形成跨平台同款（供横向对比）
        for brand, series in models:
            model = f"{brand} {series}"
            base = 10 ** rng.uniform(0, 1) * (low * high) ** 0.5  # 对数均匀分布
            base = min(max(base, low), high)
            picked = rng.sample(profiles, k=min(len(profiles), rng.choice([2, 2, 3])))
            for plat_name, koef, rmin, rmax, sales_koef in picked:
                price = base * koef * rng.uniform(0.93, 1.08)
                sales = int(rng.uniform(0.35, 0.75) * _sales_base(rng, cat) * sales_koef)
                add(plat_name, model, price, rng.uniform(rmin, rmax), sales)

        # 2) 平台独占型号：制造「只在某平台有」的场景
        for plat_name, _koef, rmin, rmax, sales_koef in profiles:
            brand, series = rng.choice(models)
            base = 10 ** rng.uniform(0, 1) * (low * high) ** 0.5
            add(plat_name, f"{brand} {series} 定制版",
                min(max(base, low), high) * rng.uniform(0.9, 1.15),
                rng.uniform(rmin, rmax), int(rng.uniform(0.2, 0.6) * _sales_base(rng, cat) * sales_koef))

        # 3) 注入重复行（同平台同店同款，价格略高）验证去重
        for row in rng.sample(rows, k=min(3, len(rows))):
            dup = dict(row)
            dup["title"] = f"【官方旗舰店】{row['title']} 包邮"
            dup["price"] = _fmt_price(rng, float(str(row["price"]).replace("¥", "").replace("券后 ", "").replace("元起", "").replace(",", "")) * rng.uniform(1.0, 1.06))
            rows.append(dup)

        # 4) 注入异常值（¥9.9 与 ¥99999）验证异常剔除
        if models:
            brand, series = models[0]
            add(self.platforms[0], f"{brand} {series}", 9.9, 4.8, 20, dirty=True)
            add(self.platforms[-1], f"{brand} {series}", 99999.0, 4.9, 3, dirty=True)

        rng.shuffle(rows)
        return rows[:limit]


def _sales_base(rng: random.Random, cat: str) -> float:
    """不同品类的销量量级差异。"""
    scale = {"audio": 1.0, "phone": 0.6, "laptop": 0.25, "peripheral": 1.4, "home": 1.8}.get(cat, 0.8)
    return (10 ** rng.uniform(1.9, 4.2)) * scale
