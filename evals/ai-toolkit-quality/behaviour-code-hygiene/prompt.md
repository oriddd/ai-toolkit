---
description: "applying `code-hygiene` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Clean up this class and its test before I open the pull request. Show the result in your reply; do not create files.

```java
/**
 * Service for order totals.
 * @author jdoe
 */
public class OrderTotals {
    /** The tax rate. */
    private final BigDecimal taxRate;

    /**
     * Constructor.
     * @param taxRate the tax rate
     */
    public OrderTotals(BigDecimal taxRate) { this.taxRate = taxRate; }

    /** Gets the tax rate. @return the tax rate */
    public BigDecimal getTaxRate() { return taxRate; }

    // calculate total
    public BigDecimal total(BigDecimal net) {
        return net.add(net.multiply(taxRate)); // add tax
    }

    // public BigDecimal oldTotal(BigDecimal net) { return net; }
}
```

```java
class OrderTotalsTest {
    @Test void getTaxRate_returnsTaxRate() {
        assertEquals(new BigDecimal("0.17"), new OrderTotals(new BigDecimal("0.17")).getTaxRate());
    }
    @Test void total_100_returns117() {
        assertEquals(new BigDecimal("117.00"), new OrderTotals(new BigDecimal("0.17")).total(new BigDecimal("100.00")));
    }
    @Test void total_200_returns234() {
        assertEquals(new BigDecimal("234.00"), new OrderTotals(new BigDecimal("0.17")).total(new BigDecimal("200.00")));
    }
}
```
