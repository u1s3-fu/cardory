"""可视化与报告渲染层：自包含 SVG 图表 + HTML 片段。

为什么用「Python 生成 SVG」而不是引入 matplotlib / ECharts
--------------------------------------------------------
1. 零依赖：命令行导出报告、网页渲染共用同一套渲染代码，
   不需要 CDN、不需要浏览器端 JS 图表库，离线可用、可归档。
2. 同一份片段既能拼成独立 HTML 报告，也能注入演示网页，
   保证「页面结果」与「CLI 导出结果」视觉与数据完全一致。
3. 图表全部用 viewBox 自适应宽度，移动端直接跟随容器缩放。

包含四类图表：
- 价格阶梯图  ：价格升序横向条形，一眼看出便宜档位与中位价参考线
- 平台价格区间：每个平台的最低价~最高价区间 + 均价标记 + 价格水位指数
- 价格分布直方：按价格分桶、平台堆叠，看出各平台的价格带重叠度
- 价格趋势折线：各平台均价与全场最低价随日期变化
"""

from __future__ import annotations

from statistics import median
from typing import Any, Dict, List, Optional

PLATFORM_COLORS: Dict[str, str] = {
    "京东": "#e23a3a",
    "淘宝": "#ff8f00",
    "拼多多": "#8e24aa",
}
FALLBACK_COLORS = ["#0ea5e9", "#10b981", "#6366f1", "#f43f5e", "#a16207"]
FONT = "system-ui,-apple-system,'Segoe UI','PingFang SC','Microsoft YaHei',sans-serif"

TAG_COLORS = {
    "全场最低价": "#059669",
    "销量之星": "#2563eb",
    "口碑之星": "#7c3aed",
    "同款最低": "#0d9488",
    "同款最高": "#94a3b8",
    "价格异常": "#dc2626",
}


# ---------------------------------------------------------------- 基础工具

def esc(value: Any) -> str:
    text = "" if value is None else str(value)
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace('"', "&quot;"))


def color_of(platform: str, index: int = 0) -> str:
    if platform in PLATFORM_COLORS:
        return PLATFORM_COLORS[platform]
    return FALLBACK_COLORS[index % len(FALLBACK_COLORS)]


def money(value: Any) -> str:
    try:
        return f"{float(value):,.2f}"
    except (TypeError, ValueError):
        return "—"


def fmt_int(value: Any) -> str:
    try:
        num = int(float(value))
    except (TypeError, ValueError):
        return "—"
    return f"{num / 10000:.1f}万" if num >= 10000 else str(num)


def _t(x: float, y: float, text: Any, size: float = 12, fill: str = "#334155",
       anchor: str = "start", weight: str = "400") -> str:
    return (f'<text x="{round(x,1)}" y="{round(y,1)}" font-size="{size}" fill="{fill}" '
            f'text-anchor="{anchor}" font-weight="{weight}">{esc(text)}</text>')


def _line(x1: float, y1: float, x2: float, y2: float, color: str,
          width: float = 1, dash: str = "") -> str:
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return (f'<line x1="{round(x1,1)}" y1="{round(y1,1)}" x2="{round(x2,1)}" y2="{round(y2,1)}" '
            f'stroke="{color}" stroke-width="{width}"{dash_attr}/>')


def _svg_open(width: int, height: int, label: str) -> str:
    return (f'<svg viewBox="0 0 {width} {height}" width="100%" role="img" '
            f'aria-label="{esc(label)}" style="font-family:{FONT};display:block">')


def _empty(message: str) -> str:
    return f'<div class="empty">{esc(message)}</div>'


# ---------------------------------------------------------------- 图表 1：价格阶梯

def svg_price_ladder(products: List[Dict[str, Any]], limit: int = 14) -> str:
    items = products[:limit]
    if not items:
        return _empty("暂无商品数据")
    width, row_h = 940, 30
    left, right = 268, 96
    plot_w = width - left - right
    max_price = max(p["price"] for p in products) or 1
    height = len(items) * row_h + 44

    parts = [_svg_open(width, height, "价格阶梯图")]
    med = median([p["price"] for p in products])
    x_med = left + plot_w * med / max_price
    parts.append(_line(x_med, 8, x_med, height - 30, "#94a3b8", 1, "4 3"))
    parts.append(_t(x_med + 4, 18, f"中位价 {money(med)}", 11, "#64748b"))

    for idx, item in enumerate(items):
        y = 30 + idx * row_h
        title = item["title"]
        short = title if len(title) <= 22 else title[:22] + "…"
        parts.append(_t(4, y + 16, short, 12, "#0f172a"))
        parts.append(_t(left - 10, y + 16, item["platform"], 11, color_of(item["platform"]), "end", "600"))
        bar_w = max(plot_w * item["price"] / max_price, 4)
        opacity = max(0.55, 0.95 - idx * 0.03)
        parts.append(f'<rect x="{left}" y="{y + 5}" width="{round(bar_w,1)}" height="16" rx="4" '
                     f'fill="{color_of(item["platform"])}" opacity="{opacity:.2f}"/>')
        parts.append(_t(left + bar_w + 8, y + 18, f"{money(item['price'])} 元", 12, "#0f172a", "start", "600"))
    parts.append("</svg>")
    return "".join(parts)


# ---------------------------------------------------------------- 图表 2：平台价格区间

def svg_platform_range(stats: List[Dict[str, Any]]) -> str:
    if not stats:
        return _empty("暂无平台数据")
    width = 940
    row_h = 52
    height = len(stats) * row_h + 56
    left, right = 92, 186
    plot_w = width - left - right
    lo = min(s["min_price"] for s in stats)
    hi = max(s["max_price"] for s in stats)
    span = max(hi - lo, 1.0)
    scale = lambda v: left + plot_w * (v - lo) / span  # noqa: E731

    parts = [_svg_open(width, height, "各平台价格区间")]
    for tick in range(5):
        value = lo + span * tick / 4
        x = scale(value)
        parts.append(_line(x, 24, x, height - 30, "#e2e8f0", 1))
        parts.append(_t(x, height - 14, f"{money(value)}", 11, "#94a3b8", "middle"))

    for idx, item in enumerate(stats):
        y = 44 + idx * row_h
        parts.append(_t(4, y + 4, item["platform"], 12, color_of(item["platform"], idx), "start", "700"))
        parts.append(f'<line x1="{round(scale(item["min_price"]),1)}" y1="{y}" '
                     f'x2="{round(scale(item["max_price"]),1)}" y2="{y}" '
                     f'stroke="{color_of(item["platform"], idx)}" stroke-width="6" opacity="0.35" stroke-linecap="round"/>')
        avg_x = scale(item["avg_price"])
        parts.append(f'<circle cx="{round(avg_x,1)}" cy="{y}" r="6" fill="{color_of(item["platform"], idx)}"/>')
        parts.append(_t(avg_x, y - 12, f"均价 {money(item['avg_price'])}", 11, "#0f172a", "middle", "600"))
        parts.append(_t(left + plot_w + 16, y - 2,
                        f"{item['count']} 款 · 销量 {fmt_int(item['total_sales'])}", 11, "#475569"))
        parts.append(_t(left + plot_w + 16, y + 14,
                        f"价格水位 {item['price_index']:.2f}×", 11,
                        "#059669" if item["price_index"] < 0.98 else
                        ("#dc2626" if item["price_index"] > 1.02 else "#64748b")))
    parts.append("</svg>")
    return "".join(parts)


# ---------------------------------------------------------------- 图表 3：价格分布直方

def svg_histogram(products: List[Dict[str, Any]], bins: int = 8) -> str:
    if not products:
        return _empty("暂无商品数据")
    prices = [p["price"] for p in products]
    lo, hi = min(prices), max(prices)
    if hi - lo < 1:
        hi = lo + 1
    step = (hi - lo) / bins
    buckets: List[Dict[str, Dict[str, int]]] = [dict() for _ in range(bins)]
    for item in products:
        idx = min(int((item["price"] - lo) / step), bins - 1)
        buckets[idx][item["platform"]] = buckets[idx].get(item["platform"], 0) + 1

    width, height = 940, 280
    left, right, top, bottom = 56, 20, 30, 58
    plot_w, plot_h = width - left - right, height - top - bottom
    max_total = max((sum(b.values()) for b in buckets), default=1) or 1
    bar_w = plot_w / bins * 0.62
    platforms = sorted({p["platform"] for p in products})

    parts = [_svg_open(width, height, "价格分布直方图")]
    for tick in range(5):
        y = top + plot_h * tick / 4
        parts.append(_line(left, y, left + plot_w, y, "#e2e8f0", 1))
        parts.append(_t(left - 8, y + 4, str(round(max_total * (1 - tick / 4))), 11, "#94a3b8", "end"))

    for idx, bucket in enumerate(buckets):
        total = sum(bucket.values())
        x = left + plot_w * (idx + 0.5) / bins - bar_w / 2
        y_cursor = top + plot_h
        for platform in platforms:
            count = bucket.get(platform, 0)
            if not count:
                continue
            h = plot_h * count / max_total
            y_cursor -= h
            parts.append(f'<rect x="{round(x,1)}" y="{round(y_cursor,1)}" width="{round(bar_w,1)}" '
                         f'height="{round(h,1)}" rx="3" fill="{color_of(platform)}" opacity="0.85"/>')
            if h > 15:
                parts.append(_t(x + bar_w / 2, y_cursor + h / 2 + 4, str(count), 11, "#ffffff", "middle", "600"))
        low_label = f"{int(lo + idx * step)}"
        high_label = f"{int(lo + (idx + 1) * step)}"
        parts.append(_t(x + bar_w / 2, top + plot_h + 18, f"{low_label}~{high_label}", 11, "#64748b", "middle"))
        parts.append(_t(x + bar_w / 2, top + plot_h + 34, f"{total} 款", 10, "#94a3b8", "middle"))

    parts.append(_t(left, 16, "款数（元 / 价格区间）", 11, "#94a3b8"))
    parts.append("</svg>")
    return "".join(parts)


# ---------------------------------------------------------------- 图表 4：价格趋势

def svg_trend(trend: Dict[str, Any]) -> str:
    series = [s for s in (trend.get("series") or []) if s.get("points")]
    dates = trend.get("dates") or []
    if not series or len(dates) < 2:
        return _empty("趋势数据不足（至少需要 2 天的采集快照才能画趋势）")

    width, height = 940, 330
    left, right, top, bottom = 74, 26, 56, 54
    plot_w, plot_h = width - left - right, height - top - bottom
    values = [pt["value"] for s in series for pt in s["points"]]
    lo, hi = min(values), max(values)
    pad = max((hi - lo) * 0.15, hi * 0.02, 1)
    lo, hi = lo - pad, hi + pad
    span = hi - lo

    x_at = lambda i: left + (plot_w * i / (len(dates) - 1) if len(dates) > 1 else plot_w / 2)  # noqa: E731
    y_at = lambda v: top + plot_h * (1 - (v - lo) / span)  # noqa: E731

    parts = [_svg_open(width, height, "价格趋势折线图")]
    for tick in range(5):
        value = hi - span * tick / 4
        y = y_at(value)
        parts.append(_line(left, y, left + plot_w, y, "#e2e8f0", 1))
        parts.append(_t(left - 10, y + 4, money(value), 11, "#94a3b8", "end"))

    label_step = max(1, len(dates) // 7)
    for i, date in enumerate(dates):
        if i % label_step and i != len(dates) - 1:
            continue
        parts.append(_t(x_at(i), top + plot_h + 20, date[5:], 11, "#64748b", "middle"))

    for idx, item in enumerate(series):
        is_best = item.get("kind") == "best"
        color = "#0f172a" if is_best else color_of(item["name"], idx)
        pts = " ".join(f"{round(x_at(dates.index(pt['date'])),1)},{round(y_at(pt['value']),1)}"
                       for pt in item["points"] if pt["date"] in dates)
        parts.append(f'<polyline points="{pts}" fill="none" stroke="{color}" '
                     f'stroke-width="{3 if is_best else 2.2}" '
                     f'stroke-dasharray="{"5 4" if is_best else ""}" stroke-linejoin="round"/>')
        for pt in item["points"]:
            if pt["date"] not in dates:
                continue
            cx, cy = x_at(dates.index(pt["date"])), y_at(pt["value"])
            parts.append(f'<circle cx="{round(cx,1)}" cy="{round(cy,1)}" r="3.6" fill="{color}"/>')
            if is_best or idx < 3:
                parts.append(_t(cx, cy - 10, f"{pt['value']:.1f}", 10, color, "middle", "600"))

    # 图例
    lx = left + 4
    for idx, item in enumerate(series):
        color = "#0f172a" if item.get("kind") == "best" else color_of(item["name"], idx)
        ly = 20
        shift = idx * 116
        parts.append(f'<rect x="{lx + shift}" y="{ly - 9}" width="18" height="3" rx="1.5" fill="{color}"/>')
        parts.append(_t(lx + shift + 24, ly - 5, item["name"], 11, "#334155"))
    parts.append("</svg>")
    return "".join(parts)


# ---------------------------------------------------------------- 表格与卡片

def _platform_badge(platform: str, index: int = 0) -> str:
    color = color_of(platform, index)
    return (f'<span class="badge" style="background:{color}1a;color:{color};'
            f'border:1px solid {color}55">{esc(platform)}</span>')


def _tag_chips(tags: List[str]) -> str:
    if not tags:
        return '<span class="muted">—</span>'
    chips = []
    for tag in tags[:3]:
        color = TAG_COLORS.get(tag, "#475569")
        chips.append(f'<span class="chip" style="background:{color}14;color:{color};'
                     f'border:1px solid {color}44">{esc(tag)}</span>')
    return "".join(chips)


def _table(headers: List[Dict[str, str]], rows: List[List[str]], cls: str = "") -> str:
    head = "".join(
        f'<th{" data-sort=\"1\"" if h.get("sort") else ""} class="{h.get("cls","")}">{esc(h["label"])}</th>'
        for h in headers
    )
    body = "".join("<tr>" + "".join(f'<td class="{c}">{c2}</td>' for c, c2 in row) + "</tr>"
                   for row in rows) if rows else \
        f'<tr><td colspan="{len(headers)}" class="empty">无数据</td></tr>'
    return (f'<div class="table-wrap"><table class="data-table {cls}">'
            f"<thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>")


def table_products(products: List[Dict[str, Any]]) -> str:
    headers = [
        {"label": "价格排名", "sort": True}, {"label": "平台", "sort": True},
        {"label": "商品", "cls": "col-title"}, {"label": "到手价(元)", "sort": True, "cls": "num"},
        {"label": "原价/折扣", "sort": True, "cls": "num"}, {"label": "月销", "sort": True, "cls": "num"},
        {"label": "店铺评分", "sort": True, "cls": "num"}, {"label": "店铺", "cls": "col-shop"},
        {"label": "标注"}, {"label": "链接"},
    ]
    rows = []
    for item in products:
        pid = item["id"]
        original = (f'{money(item["original_price"])}<br><span class="discount">-{round(item.get("discount", 0) * 100)}%</span>'
                    if item.get("original_price") else '<span class="muted">—</span>')
        platforms = item.get("extra", {}).get("group_platforms") or []
        group_note = (f'<div class="sub">同款在 {len(platforms)} 个平台：'
                      f'{esc("/".join(platforms))}</div>' if len(platforms) >= 2 else "")
        score_bar = (f'<div class="score"><div class="score-bar" style="width:{item["score"]}%"></div></div>'
                     f'<span class="sub">指数 {item["score"]}</span>')
        link = (f'<a class="btn-link" href="{esc(item["url"])}" target="_blank" rel="noopener noreferrer">查看商品</a>'
                if item.get("url") else '<span class="muted">—</span>')
        rows.append([
            ("num rank", f'<b data-v="{item["rank"]}">{item["rank"]}</b>'),
            ("", f'<span data-v="{esc(item["platform"])}">{_platform_badge(item["platform"])}</span>'),
            ("col-title", f'<div class="title">{esc(item["title"])}</div>{group_note}{score_bar}'),
            ("num", f'<b class="price" data-v="{item["price"]}">{money(item["price"])}</b>'),
            ("num", f'<span data-v="{item["original_price"] or 0}">{original}</span>'),
            ("num", f'<span data-v="{item["sales"]}">{fmt_int(item["sales"])}</span>'),
            ("num", f'<span data-v="{item["shop_rating"]}">{item["shop_rating"] or "—"}</span>'),
            ("col-shop", esc(item["shop"])),
            ("", f'<span data-v="{esc(" ".join(item["tags"]))}">{_tag_chips(item["tags"])}</span>'),
            ("", link),
        ])
    return _table(headers, rows, cls="products")


def table_groups(groups: List[Dict[str, Any]]) -> str:
    multi = [g for g in groups if g["platform_count"] >= 2]
    if not multi:
        return _empty("本次采集没有出现「同一款商品在 2 个以上平台同时有售」的情况，无法做跨平台同款比价。")

    platforms: List[str] = []
    for group in multi:
        for plat in group["platforms"]:
            if plat not in platforms:
                platforms.append(plat)
    platforms.sort(key=lambda p: (0 if p in PLATFORM_COLORS else 1, p))

    headers = [{"label": "同款商品", "cls": "col-title"}, {"label": "覆盖平台", "sort": True, "cls": "num"}]
    headers += [{"label": f"{p}价(元)", "sort": True, "cls": "num"} for p in platforms]
    headers += [{"label": "最低平台"}, {"label": "最高-最低", "sort": True, "cls": "num"},
                {"label": "选它可省", "sort": True, "cls": "num"}]

    rows = []
    for group in multi:
        cells = [
            ("col-title", f'<div class="title">{esc(group["label"])}</div>'
                          f'<div class="sub">{group["shop_count"]} 个店铺 · 合计月销 {fmt_int(group["sales_total"])}</div>'),
            ("num", f'<b data-v="{group["platform_count"]}">{group["platform_count"]}</b>'),
        ]
        for plat in platforms:
            info = group["platforms"].get(plat)
            if not info:
                cells.append(("num", '<span class="muted">—</span>'))
                continue
            is_best = plat == group["best_platform"]
            cells.append(("num", f'<span data-v="{info["price"]}" class="{"best" if is_best else ""}">'
                                 f'{money(info["price"])}</span>'))
        cells += [
            ("", _platform_badge(group["best_platform"], platforms.index(group["best_platform"]))),
            ("num", f'<span data-v="{group["saving_amount"]}">{money(group["saving_amount"])}</span>'),
            ("num", f'<span class="save" data-v="{group["saving_pct"]}">{group["saving_pct"]}%</span>'),
        ]
        rows.append(cells)
    return _table(headers, rows, cls="groups")


def cards_recommendations(recs: List[Dict[str, Any]]) -> str:
    if not recs:
        return _empty("暂无推荐")
    cards = []
    for rec in recs:
        level = rec.get("level", "info")
        product = rec.get("product")
        group = rec.get("group")
        detail = ""
        if product:
            detail = (f'<div class="card-meta">{_platform_badge(product["platform"])}'
                      f'<b>{money(product["price"])} 元</b> · 月销 {fmt_int(product["sales"])} · '
                      f'评分 {product["shop_rating"]} · {esc(product["shop"])}</div>'
                      f'<div class="card-title">{esc(product["title"])}</div>')
        elif group:
            mini = "".join(
                f'<li><span>{esc(plat)}</span><b>{money(info["price"])} 元</b></li>'
                for plat, info in sorted(group["platforms"].items(), key=lambda kv: kv[1]["price"]))
            detail = f'<ul class="mini-list">{mini}</ul>'
        elif rec.get("platform"):
            detail = (f'<div class="card-meta">{_platform_badge(rec["platform"])}'
                      f'<b>{money(rec["price"])} 元</b> · {esc(rec.get("shop", ""))}</div>'
                      f'<div class="card-title">{esc(rec.get("label", ""))}</div>')
        cards.append(
            f'<article class="rec-card level-{level}">'
            f'<div class="rec-tag">{esc(rec["tag"])}</div>'
            f'{detail}<p class="rec-reason">{esc(rec["reason"])}</p>'
            f'</article>'
        )
    return f'<div class="rec-grid">{"".join(cards)}</div>'


def summary_cards(result: Dict[str, Any]) -> str:
    clean = result.get("cleaning", {})
    price = result.get("price", {})
    items = [
        ("有效商品", f'{result.get("count", 0)}', f'采集 {clean.get("raw_count", 0)} 条 → 清洗后剩这些'),
        ("最低价", f'{money(price.get("min", 0))} 元', "全场到手价最低"),
        ("平均价", f'{money(price.get("avg", 0))} 元', f'中位价 {money(price.get("median", 0))} 元'),
        ("覆盖平台", f'{result.get("platform_count", 0)}', " / ".join(result.get("platform_list", []))),
        ("同款可比组", f'{result.get("comparable_groups", 0)}', "可在 2+ 平台横向比价的商品数"),
        ("合计月销", fmt_int(result.get("total_sales", 0)), "反映热度与市场认可度"),
        ("平均店铺评分", f'{result.get("avg_rating", 0)}', "满分 5 分"),
    ]
    cards = "".join(
        f'<div class="kpi"><div class="kpi-label">{esc(label)}</div>'
        f'<div class="kpi-value">{esc(value)}</div>'
        f'<div class="kpi-sub">{esc(sub)}</div></div>'
        for label, value, sub in items
    )
    return f'<div class="kpi-grid">{cards}</div>'


def quality_panel(result: Dict[str, Any]) -> str:
    clean = result.get("cleaning", {})
    dupes = result.get("removed_duplicates") or []
    outliers = result.get("outliers") or []

    flow = (f'<div class="flow">'
            f'<span class="flow-node">原始采集 <b>{clean.get("raw_count", 0)}</b></span>'
            f'<span class="flow-arrow">→</span>'
            f'<span class="flow-node lose">无效丢弃 <b>{clean.get("invalid_dropped", 0)}</b></span>'
            f'<span class="flow-arrow">→</span>'
            f'<span class="flow-node lose">去重 <b>{clean.get("duplicates_removed", 0)}</b></span>'
            f'<span class="flow-arrow">→</span>'
            f'<span class="flow-node lose">异常剔除 <b>{clean.get("outliers_removed", 0)}</b></span>'
            f'<span class="flow-arrow">→</span>'
            f'<span class="flow-node keep">进入分析 <b>{clean.get("valid_count", 0)}</b></span>'
            f'</div>')

    dup_table = _table(
        [{"label": "平台"}, {"label": "被丢弃（更贵/重复）", "cls": "col-title"},
         {"label": "价格", "cls": "num"}, {"label": "保留记录", "cls": "col-title"},
         {"label": "价格", "cls": "num"}, {"label": "判定依据"}],
        [[("", _platform_badge(d["platform"])),
          ("col-title", esc(d["title"])), ("num", money(d["price"])),
          ("col-title", esc(d["kept_title"])), ("num", money(d["kept_price"])),
          ("", esc(d["reason"]))] for d in dupes[:8]],
        cls="dupes",
    )
    out_table = _table(
        [{"label": "平台"}, {"label": "商品", "cls": "col-title"},
         {"label": "价格", "cls": "num"}, {"label": "剔除原因"}],
        [[("", _platform_badge(o["platform"])), ("col-title", esc(o["title"])),
          ("num", money(o["price"])), ("", esc(o.get("extra", {}).get("outlier_reason", "价格异常")))]
         for o in outliers],
        cls="outliers",
    )
    return (f'<div class="panel-block">{flow}</div>'
            f'<h4 class="sub-title">被去除的重复铺货（示例最多 8 条）</h4>{dup_table}'
            f'<h4 class="sub-title">被判为价格异常、已剔除出排名的商品</h4>{out_table}')


def raw_table(rows: List[Dict[str, Any]], limit: int = 10) -> str:
    headers = [{"label": "平台"}, {"label": "原始标题（含促销词）", "cls": "col-title"},
               {"label": "原始价格字段"}, {"label": "原始销量字段"},
               {"label": "原始评分字段"}, {"label": "原始链接"}]
    body = []
    for row in rows[:limit]:
        url = str(row.get("url") or "")
        body.append([
            ("", _platform_badge(str(row.get("platform") or ""))),
            ("col-title", esc(row.get("title"))),
            ("raw-cell", esc(row.get("price"))),
            ("raw-cell", esc(row.get("sales"))),
            ("raw-cell", esc(row.get("shop_rating"))),
            ("", f'<span class="url">{esc(url[:58])}{"…" if len(url) > 58 else ""}</span>'),
        ])
    return _table(headers, body, cls="raw")


def adapter_report_html(result: Dict[str, Any]) -> str:
    report = result.get("collect_report") or []
    if not report:
        return ""
    rows = []
    for entry in report:
        ok = entry.get("status") == "ok"
        rows.append([
            ("", _platform_badge(str(entry.get("platform", "?")))),
            ("", entry.get("adapter", "")),
            ("", f'<span class="state {"ok" if ok else "skip"}">{entry.get("status", "")}</span>'),
            ("num", f'{entry.get("rows", 0)}'),
            ("num", f'{entry.get("elapsed_ms", 0)} ms'),
            ("", esc(entry.get("reason", ""))),
        ])
    return _table([{"label": "平台"}, {"label": "适配器"}, {"label": "状态"},
                   {"label": "条数", "cls": "num"}, {"label": "耗时", "cls": "num"},
                   {"label": "说明"}], rows, cls="adapters")


# ---------------------------------------------------------------- 样式

BASE_CSS = """
:root{
  --bg:#f6f7fb; --panel:#ffffff; --ink:#0f172a; --ink-2:#475569; --ink-3:#94a3b8;
  --line:#e6eaf2; --brand:#1d4ed8; --brand-2:#0ea5e9; --ok:#059669; --warn:#d97706; --danger:#dc2626;
  --shadow:0 1px 2px rgba(15,23,42,.04),0 8px 24px -12px rgba(15,23,42,.18);
  --radius:14px;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
  font-family:system-ui,-apple-system,'Segoe UI','PingFang SC','Microsoft YaHei',sans-serif;
  font-size:14px;line-height:1.6;-webkit-font-smoothing:antialiased}
a{color:var(--brand);text-decoration:none}
a:hover{text-decoration:underline}
.wrap{max-width:1180px;margin:0 auto;padding:28px 20px 64px}
section.card{background:var(--panel);border:1px solid var(--line);border-radius:var(--radius);
  padding:22px 22px 24px;margin-bottom:20px;box-shadow:var(--shadow)}
h1{font-size:26px;margin:0 0 6px}
h2{font-size:19px;margin:0 0 4px}
h3{font-size:16px;margin:0 0 10px;color:var(--ink)}
h4.sub-title{font-size:13px;color:var(--ink-2);margin:18px 0 8px;font-weight:600}
.lede{color:var(--ink-2);font-size:13px;margin:0 0 14px}
.muted{color:var(--ink-3)}
.sub{color:var(--ink-3);font-size:12px}
.sec-head{display:flex;align-items:baseline;gap:10px;justify-content:space-between;
  border-bottom:1px solid var(--line);padding-bottom:12px;margin-bottom:16px}
.sec-head .tip{font-size:12px;color:var(--ink-3)}

/* KPI */
.kpi-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(158px,1fr));gap:12px}
.kpi{background:linear-gradient(180deg,#fbfcff,#f4f7ff);border:1px solid var(--line);
  border-radius:12px;padding:14px}
.kpi-label{font-size:12px;color:var(--ink-3)}
.kpi-value{font-size:22px;font-weight:700;letter-spacing:-.3px;color:var(--ink);margin:2px 0}
.kpi-sub{font-size:11px;color:var(--ink-3)}

/* 表格 */
.table-wrap{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:#fff}
table.data-table{border-collapse:collapse;width:100%;min-width:640px;font-size:13px}
table.data-table th{background:#f8fafc;text-align:left;font-weight:600;color:var(--ink-2);
  padding:10px 12px;border-bottom:1px solid var(--line);white-space:nowrap;font-size:12px}
table.data-table th[data-sort]{cursor:pointer;user-select:none}
table.data-table th[data-sort]:after{content:" ⇅";color:var(--ink-3);font-size:10px}
table.data-table th[data-dir="asc"]:after{content:" ↑";color:var(--brand)}
table.data-table th[data-dir="desc"]:after{content:" ↓";color:var(--brand)}
table.data-table td{padding:10px 12px;border-bottom:1px solid #f1f5f9;vertical-align:middle}
table.data-table tbody tr:hover{background:#fafbff}
table.data-table tr:last-child td{border-bottom:none}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
.col-title{min-width:260px;max-width:420px}
.col-shop{max-width:190px}
.title{font-weight:600;color:var(--ink);line-height:1.45}
.price{color:var(--danger);font-size:15px}
.best{color:var(--ok);font-weight:700;background:#ecfdf5;border-radius:6px;padding:2px 6px}
.save{color:var(--ok);font-weight:600}
.discount{color:var(--warn);font-size:11px}
.rank{color:var(--ink-3)}
.raw-cell{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--warn)}
.url{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11px;color:var(--ink-3)}

/* 徽标 */
.badge{display:inline-block;padding:2px 8px;border-radius:999px;font-size:11px;font-weight:600;white-space:nowrap}
.chip{display:inline-block;padding:2px 7px;border-radius:6px;font-size:11px;margin:0 2px 2px 0;white-space:nowrap}
.score{margin-top:6px;height:5px;background:#eef2f8;border-radius:4px;overflow:hidden;max-width:180px}
.score-bar{height:100%;background:linear-gradient(90deg,var(--brand-2),var(--brand))}
.btn-link{display:inline-block;padding:4px 10px;border:1px solid var(--line);border-radius:8px;
  font-size:12px;background:#fff;white-space:nowrap}
.btn-link:hover{border-color:var(--brand);background:#f5f8ff;text-decoration:none}
.state{font-weight:600}
.state.ok{color:var(--ok)}
.state.skip{color:var(--warn)}

/* 推荐卡 */
.rec-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px}
.rec-card{border:1px solid var(--line);border-left:4px solid var(--brand);border-radius:12px;
  padding:14px 16px;background:#fff}
.rec-card.level-primary{border-left-color:var(--ok);background:linear-gradient(180deg,#f4fdf9,#fff)}
.rec-card.level-warn{border-left-color:var(--warn);background:linear-gradient(180deg,#fffbf3,#fff)}
.rec-tag{display:inline-block;font-size:12px;font-weight:700;color:var(--brand);margin-bottom:6px}
.rec-card.level-primary .rec-tag{color:var(--ok)}
.rec-card.level-warn .rec-tag{color:var(--warn)}
.card-title{font-size:13px;font-weight:600;margin:2px 0 4px}
.card-meta{display:flex;align-items:center;gap:8px;font-size:12px;color:var(--ink-2);flex-wrap:wrap}
.rec-reason{margin:8px 0 0;font-size:12.5px;color:var(--ink-2)}
.mini-list{list-style:none;margin:6px 0 0;padding:0;display:flex;gap:12px;flex-wrap:wrap}
.mini-list li{font-size:12px;color:var(--ink-2)}
.mini-list b{margin-left:6px;color:var(--ink)}

/* 清洗流程 */
.flow{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.flow-node{padding:8px 12px;border-radius:10px;background:#f1f5f9;font-size:12px;color:var(--ink-2)}
.flow-node b{color:var(--ink);margin-left:4px}
.flow-node.lose{background:#fff7ed;color:#b45309}
.flow-node.keep{background:#ecfdf5;color:#047857}
.flow-arrow{color:var(--ink-3)}

/* 图表 */
.chart{margin-top:6px}
.chart-note{font-size:11.5px;color:var(--ink-3);margin-top:6px}
.empty{padding:18px;text-align:center;color:var(--ink-3);font-size:12.5px;
  border:1px dashed var(--line);border-radius:10px;background:#fbfcfe}
.split{display:grid;grid-template-columns:1fr;gap:18px}
@media(min-width:900px){.split-2{grid-template-columns:1fr 1fr}}
"""

TABLE_SCRIPT = """
(function(){
  const key = v => { const n = parseFloat(String(v).replace(/[^\\d.\\-]/g,'')); 
    return isFinite(n) && /[0-9]/.test(String(v)) ? n : String(v); };
  document.addEventListener('click', function(e){
    const th = e.target.closest('th[data-sort]'); if(!th) return;
    const table = th.closest('table'), body = table.tBodies[0];
    const idx = Array.prototype.indexOf.call(th.parentNode.children, th);
    const dir = th.dataset.dir === 'asc' ? 'desc' : 'asc'; th.dataset.dir = dir;
    const rows = Array.prototype.slice.call(body.rows);
    rows.sort(function(a,b){
      const cellA = a.cells[idx], cellB = b.cells[idx];
      const va = cellA.dataset.v !== undefined ? cellA.dataset.v : cellA.textContent;
      const vb = cellB.dataset.v !== undefined ? cellB.dataset.v : cellB.textContent;
      const ka = key(va), kb = key(vb);
      let r;
      if(typeof ka === 'number' && typeof kb === 'number') r = ka - kb;
      else r = String(ka).localeCompare(String(kb),'zh');
      return dir === 'asc' ? r : -r;
    });
    rows.forEach(function(row){ body.appendChild(row); });
  });
})();
"""


# ---------------------------------------------------------------- 片段组装

def render_fragments(result: Dict[str, Any]) -> Dict[str, str]:
    """把分析结果渲染成可独立插入页面的 HTML 片段。"""
    products = result.get("products") or []
    groups = result.get("groups") or []
    recs = result.get("recommendations") or []
    trend = result.get("trend") or {}
    roles = result.get("roles") or {}

    trend_note = "趋势基于本地历史快照累积；" + (
        f"其中包含 {trend.get('snapshot_count', 0)} 个快照" if trend else "尚无快照")
    if trend.get("synthetic"):
        trend_note += "（含首次运行时的合成回溯点，用于演示趋势形态）"

    return {
        "summary": summary_cards(result),
        "ladder": svg_price_ladder(products),
        "platform": svg_platform_range(result.get("platform_stats") or []),
        "platform_table": _table(
            [{"label": "平台"}, {"label": "款数", "sort": True, "cls": "num"},
             {"label": "最低价", "sort": True, "cls": "num"}, {"label": "均价", "sort": True, "cls": "num"},
             {"label": "最高价", "sort": True, "cls": "num"}, {"label": "合计月销", "sort": True, "cls": "num"},
             {"label": "平均评分", "sort": True, "cls": "num"}, {"label": "价格水位", "sort": True, "cls": "num"}],
            [[("", f'<span data-v="{esc(s["platform"])}">{_platform_badge(s["platform"])}</span>'),
              ("num", f'<span data-v="{s["count"]}">{s["count"]}</span>'),
              ("num", f'<span data-v="{s["min_price"]}">{money(s["min_price"])}</span>'),
              ("num", f'<span data-v="{s["avg_price"]}">{money(s["avg_price"])}</span>'),
              ("num", f'<span data-v="{s["max_price"]}">{money(s["max_price"])}</span>'),
              ("num", f'<span data-v="{s["total_sales"]}">{fmt_int(s["total_sales"])}</span>'),
              ("num", f'<span data-v="{s["avg_rating"]}">{s["avg_rating"]}</span>'),
              ("num", f'<span data-v="{s["price_index"]}">{s["price_index"]:.2f}×</span>')]
             for s in (result.get("platform_stats") or [])], cls="platforms"),
        "histogram": svg_histogram(products),
        "trend": svg_trend(trend),
        "trend_note": trend_note,
        "table": table_products(products),
        "groups": table_groups(groups),
        "recommend": cards_recommendations(recs),
        "quality": quality_panel(result),
        "raw": raw_table(result.get("raw_sample") or []),
        "adapters": adapter_report_html(result),
        "source_note": roles.get("source_note", ""),
        "generated_at": result.get("generated_at", ""),
        "keyword": result.get("keyword", ""),
        "elapsed_ms": result.get("elapsed_ms", 0),
    }


def render_page(result: Dict[str, Any], subtitle: str = "") -> str:
    """生成完全自包含（无外部依赖）的 HTML 报告文件。"""
    frag = render_fragments(result)
    kw = esc(result.get("keyword", ""))
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{kw} · 价格采集对比报告</title>
<style>{BASE_CSS}</style>
</head>
<body>
<div class="wrap">
  <header class="card">
    <h1>「{kw}」跨平台价格采集与对比报告</h1>
    <p class="lede">关键词 <b>{kw}</b> · 数据源 {esc(result.get("source", ""))} · 生成于 {esc(frag["generated_at"])} · 耗时 {frag["elapsed_ms"]} ms
      {"· " + esc(subtitle) if subtitle else ""}</p>
    {frag["source_note"]}
    <div class="sec-head" style="border:none;padding:0;margin:12px 0 0"><span class="tip"></span></div>
    {frag["summary"]}
  </header>

  <section class="card">
    <div class="sec-head"><h2>1 · 采集与清洗</h2><span class="tip">原始脏数据 → 可比较的干净数据</span></div>
    {frag["adapters"]}
    <div style="height:14px"></div>
    {frag["quality"]}
  </section>

  <section class="card">
    <div class="sec-head"><h2>2 · 性价比推荐标注</h2><span class="tip">每条推荐都给出可核对的理由</span></div>
    {frag["recommend"]}
  </section>

  <section class="card">
    <div class="sec-head"><h2>3 · 价格可视化</h2><span class="tip">阶梯 / 区间 / 分布 / 趋势</span></div>
    <div class="split">
      <div><h3>各平台价格水位与区间</h3>{frag["platform"]}{frag["platform_table"]}</div>
      <div><h3>价格阶梯（最便宜 {min(14, len(result.get("products") or []))} 款）</h3>{frag["ladder"]}</div>
      <div><h3>价格区间分布（按平台堆叠）</h3>{frag["histogram"]}</div>
      <div><h3>价格趋势</h3>{frag["trend"]}<div class="chart-note">{esc(frag["trend_note"])}</div></div>
    </div>
  </section>

  <section class="card">
    <div class="sec-head"><h2>4 · 跨平台同款横向对比</h2><span class="tip">同一款商品在不同平台的报价差异</span></div>
    {frag["groups"]}
  </section>

  <section class="card">
    <div class="sec-head"><h2>5 · 全量商品清单（价格升序）</h2><span class="tip">点击表头可排序</span></div>
    {frag["table"]}
  </section>

  <section class="card">
    <div class="sec-head"><h2>6 · 原始采集数据示例</h2><span class="tip">清洗前的脏数据长什么样</span></div>
    {frag["raw"]}
  </section>

  <footer class="lede">本报告由 ecompt 命令行工具生成 · 演示数据源为内置仿真适配器 ·
  真实平台采集请使用官方开放平台 API 或已授权数据服务。</footer>
</div>
<script>{TABLE_SCRIPT}</script>
</body>
</html>
"""
