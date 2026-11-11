set -euo pipefail
mkdir -p src/orders/api tests
cat > pyproject.toml <<'EOF'
[project]
name = "orders"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["fastapi>=0.115", "pydantic>=2.9", "sqlalchemy>=2.0"]
EOF
touch src/orders/__init__.py src/orders/api/__init__.py
cat > src/orders/main.py <<'EOF'
from fastapi import FastAPI
from orders.api.orders import router

app = FastAPI()
app.include_router(router)
EOF
cat > src/orders/api/orders.py <<'EOF'
from fastapi import APIRouter
import requests

router = APIRouter(prefix="/api/v1/orders")
PAYMENT_URL = "http://localhost:8081"
ORDERS: dict[str, dict] = {}


@router.post("")
def create(order: dict):
    if order.get("quantity", 0) <= 0:
        raise Exception("bad quantity")
    ORDERS[order["id"]] = order
    requests.post(PAYMENT_URL + "/payments", json=order)
    return order
EOF
