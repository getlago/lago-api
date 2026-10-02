"""Verify REST and GraphQL against seed_payments_filters.rb's local manifest.

Run on the host with Python 3.9+: python3 script/qa_payments_filters.py
The dev API must listen on 127.0.0.1:3000 (override with LAGO_API_URL). No credentials enter the report.
"""

import datetime as dt
import json
import os
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[1]
BASE = os.environ.get("LAGO_API_URL", "http://127.0.0.1:3000")
CREDENTIALS = json.loads((ROOT / "tmp/payments_filters_credentials.json").read_text())
MANIFEST = json.loads((ROOT / "tmp/payments_filters_manifest.json").read_text())
VISIBLE = [p for p in MANIFEST["payments"] if p["visible"]]
ZONE = ZoneInfo(MANIFEST["timezone"])
REPORT = []
TYPES = {
    "payment_status": "[PayablePaymentStatusEnum!]",
    "amount_from": "BigInt", "amount_to": "BigInt",
    "receipt_number": "String", "created_at_from": "ISO8601Date", "created_at_to": "ISO8601Date",
    "payment_provider_type": "[ProviderTypeEnum!]",
    "currency": "CurrencyEnum", "invoice_number": "String", "external_customer_id": "ID",
    "invoice_id": "ID", "payment_type": "[PaymentTypeEnum!]", "payable_type": "[PayableTypeEnum!]",
    "search_term": "String",
}


def request(path, token=None, body=None):
    headers = {"Content-Type": "application/json", "x-lago-organization": MANIFEST["organization_id"]}
    if token:
        headers["Authorization"] = "Bearer " + token
    payload = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(urllib.request.Request(BASE + path, data=payload, headers=headers), timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)


def normalized(params):
    return {"payment_status" if k == "payment_statuses" else k: v for k, v in params.items()}


def matches(payment, params):
    params = normalized(params)
    for key, value in params.items():
        if key in {"page", "per_page"}:
            continue
        if key in {"amount_from", "amount_to"}:
            amount = int(payment["amount_cents"])
            if (key == "amount_from" and amount < int(value)) or (key == "amount_to" and amount > int(value)):
                return False
        elif key in {"created_at_from", "created_at_to"}:
            try:
                bound = dt.date.fromisoformat(value)
            except ValueError:
                continue
            day = dt.datetime.fromisoformat(payment["created_at"].replace("Z", "+00:00")).astimezone(ZONE).date()
            if (key == "created_at_from" and day < bound) or (key == "created_at_to" and day > bound):
                return False
        elif key == "invoice_number":
            if value.lower() not in [n.lower() for n in payment["invoice_numbers"]]:
                return False
        elif key == "invoice_id":
            if value not in payment["invoice_ids"]:
                return False
        elif key == "receipt_number":
            if (payment["receipt_number"] or "").lower() != value.lower():
                return False
        elif key == "search_term":
            # These QA cases deliberately use provider IDs/reference, whose
            # expected values are captured independently by the seed script.
            terms = [payment["provider_payment_id"], payment["reference"]]
            if not any(value.lower() in (term or "").lower() for term in terms):
                return False
        elif payment[key] not in (value if isinstance(value, list) else [value]):
            return False
    return True


def rest(params, customer=False):
    effective = {**params, **({"external_customer_id": "cust_1"} if customer else {})}
    expected = {p["id"]: p for p in VISIBLE if matches(p, effective)}
    path = "/api/v1/customers/cust_1/payments" if customer else "/api/v1/payments"
    query = [(k + "[]", item) for k, v in params.items() if isinstance(v, list) for item in v]
    query += [(k, v) for k, v in params.items() if not isinstance(v, list)]
    url = path + "?" + urllib.parse.urlencode(query)
    status, data = request(url, CREDENTIALS["api_key"])
    assert status == 200, (url, status, data)
    assert data["meta"]["total_count"] == len(expected), (url, data["meta"], len(expected))
    actual = {p["lago_id"] for p in data["payments"]}
    assert actual == set(expected), (url, actual, set(expected))
    for payment in data["payments"]:
        assert payment["amount_cents"] == int(expected[payment["lago_id"]]["amount_cents"])
    REPORT.append({"request": "GET " + url, "status": status, "count": len(expected), "ids_match": True})


def graphql(params, token):
    params = normalized(params)
    variables, declarations, arguments = {}, [], []
    for key, value in params.items():
        name = key.split("_")[0] + "".join(part.title() for part in key.split("_")[1:])
        declarations.append("$" + name + ": " + TYPES[key])
        arguments.append(name + ": $" + name)
        variables[name] = [value] if TYPES[key].startswith("[") and not isinstance(value, list) else value
    signature = "(" + ", ".join(declarations) + ")" if declarations else ""
    args = ", ".join([*arguments, "limit: 100"])
    query = "query" + signature + " { payments(" + args + ") { collection { id amountCents } metadata { totalCount } } }"
    status, data = request("/graphql", token, {"query": query, "variables": variables})
    assert status == 200 and not data.get("errors"), (params, status, data)
    expected = {p["id"]: p for p in VISIBLE if matches(p, params)}
    result = data["data"]["payments"]
    assert result["metadata"]["totalCount"] == len(expected), (params, result, len(expected))
    assert {p["id"] for p in result["collection"]} == set(expected), params
    for payment in result["collection"]:
        assert payment["amountCents"] == expected[payment["id"]]["amount_cents"]
    REPORT.append({"request": "GraphQL payments", "variables": variables, "status": status, "count": len(expected), "ids_match": True})


login_status, login = request("/graphql", body={
    "query": "mutation($input: LoginUserInput!) { loginUser(input: $input) { token } }",
    "variables": {"input": {"email": CREDENTIALS["email"], "password": CREDENTIALS["password"]}},
})
assert login_status == 200 and not login.get("errors"), "Seeded user login failed"
TOKEN = login["data"]["loginUser"]["token"]
CASES = [
    {}, {"payment_status": ["succeeded", "failed"]}, {"payment_statuses": ["processing"]},
    {"amount_from": "1000", "amount_to": "5000"}, {"amount_from": "5000000000"},
    {"amount_from": "9007199254740993", "amount_to": "9007199254740993"},
    {"amount_from": "9223372036854775807"}, {"amount_from": "0", "amount_to": "0"},
    {"receipt_number": "rcpt-2026-0001"}, {"receipt_number": "missing"},
    {"created_at_from": "2026-09-01", "created_at_to": "2026-09-07"},
    {"payment_provider_type": ["stripe"]}, {"payment_provider_type": ["gocardless"]},
    {"currency": "EUR"},
    {"invoice_number": "lag-1234-001-002"}, {"external_customer_id": "cust_1"},
    {"payment_type": "manual", "payable_type": "PaymentRequest"}, {"search_term": "pi_3"},
    {"payment_status": "succeeded", "currency": "EUR", "amount_from": "100", "created_at_from": "2026-09-01"},
    {"payment_status": ["succeeded"], "currency": "EUR", "search_term": "pi_3"},
]
for case in CASES:
    rest(case)
    rest(case, customer=True)
    graphql(case, TOKEN)
rest({"created_at_from": "invalid", "created_at_to": "2026-02-30"})

for params in [
    {"payment_status": "bogus"}, {"payment_provider_type": "bogus"},
    {"payment_type": "bogus"}, {"payable_type": "bogus"}, {"currency": "XYZ"},
    {"amount_from": "-1"}, {"amount_to": "-1"}, {"amount_from": "500", "amount_to": "100"},
    {"amount_from": "9223372036854775808"}, {"invoice_id": "invalid"},
    {"receipt_number": "x" * 256}, {"invoice_number": "x" * 256},
]:
    url = "/api/v1/payments?" + urllib.parse.urlencode(params)
    status, data = request(url, CREDENTIALS["api_key"])
    assert status == 422 and data["code"] == "validation_errors", (params, status, data)
    REPORT.append({"request": "GET " + url, "status": status, "validation_error": True})

params = {"payment_status": "succeeded", "currency": "EUR", "amount_from": "100", "created_at_from": "2026-09-01"}
expected = {p["id"] for p in VISIBLE if matches(p, params)}
seen, page = set(), 1
while page:
    url = "/api/v1/payments?" + urllib.parse.urlencode({**params, "per_page": 2, "page": page})
    status, data = request(url, CREDENTIALS["api_key"])
    assert status == 200 and data["meta"]["total_count"] == len(expected)
    ids = {p["lago_id"] for p in data["payments"]}
    assert not seen.intersection(ids) and ids.issubset(expected)
    seen.update(ids)
    REPORT.append({"request": "GET " + url, "status": status, "meta": data["meta"], "ids_match": True})
    page = data["meta"]["next_page"]
assert seen == expected
(ROOT / "tmp/payments_filters_qa.json").write_text(json.dumps(REPORT, indent=2))
print(f"PASS: {len(REPORT)} live HTTP checks; REST, customer REST, and GraphQL match the seed manifest.")
