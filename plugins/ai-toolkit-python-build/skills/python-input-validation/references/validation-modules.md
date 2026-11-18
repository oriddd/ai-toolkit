# python-input-validation — request models, rule objects and their tests

Back to [`SKILL.md`](../SKILL.md) §2 to §4. The reusable validated types, the request models, a rule object that
needs a collaborator (the billing gateway of `python-external-client`) and the table-driven tests.

## Validated types and request models

### `src/my_service/models/types.py`

```python
from typing import Annotated

from pydantic import EmailStr, Field, StringConstraints

Email = Annotated[EmailStr, StringConstraints(max_length=254, to_lower=True)]
PositiveCents = Annotated[int, Field(gt=0, le=100_000_000, description="Amount in cents")]
```

### `src/my_service/models/requests.py`

```python
from pydantic import BaseModel, ConfigDict, Field

from my_service.models.types import Email, PositiveCents


class CreateOrderRequest(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    customer_email: Email = Field(repr=False)
    customer_id: str = Field(min_length=1, max_length=64)
    total_cents: PositiveCents
    coupon: str | None = Field(default=None, pattern=r"^[A-Z0-9]{6,12}$")


class PayOrderRequest(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    version: int = Field(ge=1)
```

## Rule objects

### `src/my_service/validation/rules.py`

```python
from typing import Protocol

from my_service.clients.billing.port import BillingGateway
from my_service.errors.domain import InsufficientCreditError
from my_service.models.requests import CreateOrderRequest


class Rule[T](Protocol):
    async def check(self, value: T) -> None: ...


class SufficientCreditRule:
    def __init__(self, billing: BillingGateway) -> None:
        self._billing = billing

    async def check(self, value: CreateOrderRequest) -> None:
        credit = await self._billing.get_credit(value.customer_id)
        if credit.available_cents < value.total_cents:
            raise InsufficientCreditError(customer_id=value.customer_id)
```

## Tests

### `tests/unit/test_validation.py`

```python
import pytest
from pydantic import ValidationError

from my_service.errors.domain import CustomerNotFoundError
from my_service.models.requests import CreateOrderRequest
from my_service.validation.rules import SufficientCreditRule
from tests.fakes.doubles import FakeBillingGateway


def _request(*, total_cents: int = 500) -> CreateOrderRequest:
    return CreateOrderRequest(customer_email="a@b.co", customer_id="c-1", total_cents=total_cents)


async def test_rule_unknownCustomer_propagatesTheGatewayError() -> None:
    rule = SufficientCreditRule(FakeBillingGateway())
    with pytest.raises(CustomerNotFoundError):
        await rule.check(_request())


@pytest.mark.parametrize(
    ("cents", "valid"),
    [(0, False), (1, True), (100_000_000, True), (100_000_001, False)],
    ids=["zero", "min", "max", "above_max"],
)
def test_createOrderRequest_totalCentsBoundaries_acceptsOnlyInRange(
    cents: int, valid: bool
) -> None:
    if valid:
        assert _request(total_cents=cents).total_cents == cents
    else:
        with pytest.raises(ValidationError):
            _request(total_cents=cents)


def test_createOrderRequest_email_isNormalisedAndHiddenFromRepr() -> None:
    request = CreateOrderRequest(customer_email="Jane@Example.COM", customer_id="c", total_cents=1)
    assert request.customer_email == "jane@example.com"
    assert "example.com" not in repr(request)


def test_createOrderRequest_unknownField_isRejected() -> None:
    with pytest.raises(ValidationError):
        CreateOrderRequest.model_validate(
            {"customer_email": "a@b.co", "customer_id": "c", "total_cents": 1, "id": "x"}
        )


@pytest.mark.parametrize("coupon", ["abc", "ABCDEF1234567", "abcdef"])
def test_createOrderRequest_badCoupon_isRejected(coupon: str) -> None:
    with pytest.raises(ValidationError):
        CreateOrderRequest(customer_email="a@b.co", customer_id="c", total_cents=1, coupon=coupon)
```
