# Load test: baseline_1client (http)

1 concurrent clients, 15s per case, synthetic dataset.

| case | selective | requests | req/s | p50 ms | p95 ms | p99 ms | max ms | errors |
|---|---|---|---|---|---|---|---|---|
| control | false | 1 | 0.1 | 26468.9 | 26468.9 | 26468.9 | 26468.9 | 0 |
| control_page50 | false | 1 | 0.1 | 15997.0 | 15997.0 | 15997.0 | 15997.0 | 0 |
| status_common_succeeded | false | 1 | 0.1 | 15380.1 | 15380.1 | 15380.1 | 15380.1 | 0 |
| status_common_succeeded_page50 | false | 2 | 0.1 | 14238.7 | 15483.5 | 15483.5 | 15483.5 | 0 |
| status_rare_failed | true | 2 | 0.1 | 6716.2 | 10526.8 | 10526.8 | 10526.8 | 0 |
| status_rare_pending | true | 3 | 0.2 | 5988.5 | 6993.1 | 6993.1 | 6993.1 | 0 |
| status_rare_processing | true | 14 | 0.9 | 798.8 | 4669.0 | 4669.0 | 4669.0 | 0 |
| status_rare_pending_processing | true | 3 | 0.2 | 6250.1 | 6333.1 | 6333.1 | 6333.1 | 0 |
| amount_common_from_p50 | false | 1 | 0.1 | 24126.8 | 24126.8 | 24126.8 | 24126.8 | 0 |
| amount_rare_from_p99 | true | 15 | 1.0 | 835.8 | 2475.7 | 2475.7 | 2475.7 | 0 |
| amount_rare_range | true | 19 | 1.3 | 801.9 | 1032.3 | 1032.3 | 1032.3 | 0 |
| created_7d | true | 73 | 4.9 | 197.1 | 266.4 | 409.7 | 409.7 | 0 |
| created_24m | false | 1 | 0.1 |  |  |  |  | 1 |
| currency_common | false | 1 | 0.1 | 16641.1 | 16641.1 | 16641.1 | 16641.1 | 0 |
| currency_rare | true | 16 | 1.1 | 823.0 | 1913.3 | 1913.3 | 1913.3 | 0 |
| provider_common | false | 1 | 0.1 |  |  |  |  | 1 |
| provider_rare | true | 2 | 0.1 | 8395.9 | 11425.6 | 11425.6 | 11425.6 | 0 |
| provider_miss | true | 1 | 0.1 |  |  |  |  | 1 |
| method_common_json | false | 1 | 0.1 | 28040.8 | 28040.8 | 28040.8 | 28040.8 | 0 |
| method_rare_json | true | 1 | 0.1 | 20676.1 | 20676.1 | 20676.1 | 20676.1 | 0 |
| method_fallback_only | true | 1 | 0.1 | 21425.2 | 21425.2 | 21425.2 | 21425.2 | 0 |
| method_multi | false | 1 | 0.1 | 20004.2 | 20004.2 | 20004.2 | 20004.2 | 0 |
| receipt_hit | true | 1 | 0.1 |  |  |  |  | 1 |
| receipt_miss | true | 1 | 0.1 |  |  |  |  | 1 |
| invoice_hit_direct | true | 1 | 0.1 |  |  |  |  | 1 |
| invoice_hit_request | true | 1 | 0.1 |  |  |  |  | 1 |
| invoice_miss | true | 1 | 0.1 |  |  |  |  | 1 |
| customer_heavy | true | 13 | 0.9 | 1048.3 | 2233.1 | 2233.1 | 2233.1 | 0 |
| customer_light | true | 76 | 5.1 | 192.3 | 243.6 | 276.2 | 276.2 | 0 |
| payment_type_manual | false | 3 | 0.2 | 5490.2 | 7560.9 | 7560.9 | 7560.9 | 0 |
| payment_type_provider | false | 1 | 0.1 | 22763.9 | 22763.9 | 22763.9 | 22763.9 | 0 |
| payable_type_request | false | 21 | 1.4 | 645.1 | 1052.5 | 1621.4 | 1621.4 | 0 |
| payable_type_invoice | false | 1 | 0.1 | 25915.4 | 25915.4 | 25915.4 | 25915.4 | 0 |
| search_term | true | 51 | 3.4 | 278.7 | 419.7 | 455.4 | 455.4 | 0 |
| search_term_status | true | 53 | 3.5 | 282.9 | 325.7 | 359.2 | 359.2 | 0 |
| combo_status_currency_date | true | 75 | 5.0 | 194.1 | 239.0 | 346.5 | 346.5 | 0 |
| combo_status_amount | true | 4 | 0.3 | 4668.6 | 4994.0 | 4994.0 | 4994.0 | 0 |
| combo_customer_status_date | true | 16 | 1.1 | 899.8 | 1869.5 | 1869.5 | 1869.5 | 0 |
| combo_provider_status | true | 1 | 0.1 | 15857.5 | 15857.5 | 15857.5 | 15857.5 | 0 |
| five_filter_common | false | 1 | 0.1 | 25135.9 | 25135.9 | 25135.9 | 25135.9 | 0 |
| five_filter_rare | true | 71 | 4.7 | 208.0 | 248.9 | 282.9 | 282.9 | 0 |
