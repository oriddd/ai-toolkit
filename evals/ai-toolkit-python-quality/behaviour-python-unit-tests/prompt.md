---
description: "applying `python-unit-tests` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

Write pytest unit tests, in your reply, for this Python class. Do not create files.

```python
class TierClient(Protocol):
    async def tier_of(self, customer_id: str) -> Tier: ...


class DiscountCalculator:
    def __init__(self, tiers: TierClient) -> None:
        self._tiers = tiers

    async def discount_for(self, customer_id: str, amount: Decimal) -> Decimal:
        if amount < 0:
            raise ValueError("amount must not be negative")
        tier = await self._tiers.tier_of(customer_id)
        return amount * {Tier.GOLD: Decimal("0.10"), Tier.SILVER: Decimal("0.05")}.get(tier, Decimal(0))
```
