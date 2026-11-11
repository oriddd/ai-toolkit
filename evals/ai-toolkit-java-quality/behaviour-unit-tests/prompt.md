---
description: "applying `unit-tests` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Write JUnit 5 unit tests, in your reply, for this Spring Boot class. Do not create files.

```java
@Service
@RequiredArgsConstructor
public class DiscountCalculator {
    private final CustomerTierClient tierClient;

    public BigDecimal discountFor(String customerId, BigDecimal amount) {
        if (amount.signum() < 0) throw new IllegalArgumentException("amount must not be negative");
        Tier tier = tierClient.tierOf(customerId);
        return switch (tier) {
            case GOLD -> amount.multiply(new BigDecimal("0.10"));
            case SILVER -> amount.multiply(new BigDecimal("0.05"));
            case NONE -> BigDecimal.ZERO;
        };
    }
}
```
