# Payments list filter QA

All records used here are synthetic and live in an isolated development organization.

- `api-qa.json`: 75 live HTTP checks across REST, customer-scoped REST and GraphQL. Each successful call asserts the filtered count and every returned ID against the seed manifest. Error cases assert status and validation details.
- Query plans and load tests live in `script/perf/payments_filters/` (synthetic 5M-payment dataset, reproducible); see its README.
- `cross-client-qa.json`: UI, REST, GraphQL, all six SDKs and CLI return the same seven succeeded EUR payments. Customer-scoped SDK calls return two; minimum amount 9223372036854775807 returns two. CLI additionally verifies arrays and saved payment method fallback.

Replay with the API development container running:

```sh
lago exec api bundle exec rails runner script/seed_payments_filters.rb
python3 script/qa_payments_filters.py
```

The seed is development-only and repeatable. It creates 30 payments (29 visible), three customers, stubbed Stripe/GoCardless providers, every status/type/method, receipts, both payable paths, multiple currencies, exact int64 bounds, and organization-timezone boundary timestamps. Local credentials are written only under ignored `tmp/` with mode 0600; do not commit them. The QA script reads those credentials without printing them. Generated IDs change in a new database, so the QA script uses the freshly generated manifest.

The actual `Invoice::VISIBLE_STATUS` includes draft. Existing visibility is preserved: the draft fixture is visible and the open-invoice fixture remains hidden. REST ignores malformed dates; GraphQL's existing ISO8601Date scalar rejects malformed dates before resolution. Existing REST errors use `validation_errors` (plural). Pagination returns a page number in `meta.next_page`, so callers repeat filters on subsequent requests.

Bullet reports pre-existing lazy loads of customer, payable, payment receipt and payment provider in both filtered and unfiltered list responses. These changes add SQL predicates without adding serialized associations or per-row association access. No serializer changes, payment response shape changes, CSV export or data-export code.
