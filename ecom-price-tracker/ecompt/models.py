"""统一数据模型。

无论数据来自哪个平台（京东 / 淘宝 / 拼多多 / 自有 API），
采集层都必须输出同构的 raw row，清洗层统一归一化为 Product。
"""

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class Product:
    """跨平台归一化后的商品实体。"""

    id: str                      # 平台内唯一 ID（或 url / title 的哈希）
    platform: str                # 平台名：京东 / 淘宝 / 拼多多
    title: str                   # 清洗后的商品标题
    price: float                 # 到手价（元）
    keyword: str = ""            # 采集关键词
    sales: int = 0               # 月销量
    comments: int = 0            # 累计评价数
    shop: str = ""               # 店铺名
    shop_rating: float = 0.0     # 店铺评分（0~5）
    url: str = ""                # 商品/店铺链接
    original_price: Optional[float] = None
    group_key: str = ""          # 同款分组键（跨平台对齐用）
    group_label: str = ""        # 同款分组展示名
    captured_at: str = ""        # 采集时间（ISO8601）
    score: float = 0.0           # 性价比指数 0~100
    rank: int = 0                # 价格升序排名
    tags: List[str] = field(default_factory=list)
    extra: Dict[str, Any] = field(default_factory=dict)

    # ---- 派生字段 ----
    @property
    def discount(self) -> float:
        """折扣率（相对原价），无原价时为 0。"""
        if self.original_price and self.original_price > self.price > 0:
            return round((self.original_price - self.price) / self.original_price, 4)
        return 0.0

    def to_dict(self) -> Dict[str, Any]:
        d = asdict(self)
        d["discount"] = self.discount
        return d

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Product":
        known = set(cls.__dataclass_fields__)
        return cls(**{k: v for k, v in data.items() if k in known})
