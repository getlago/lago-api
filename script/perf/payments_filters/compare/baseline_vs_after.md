# Before/after: baseline -> after

Plans: median EXPLAIN (ANALYZE, BUFFERS) execution time. HTTP: p95 of GET /api/v1/payments, 20 clients. Synthetic dataset.

| case | sel. | list ms before | list ms after | count ms before | count ms after | http p95 before | http p95 after | sql p95 before | sql p95 after | list nodes after | flags before | flags after |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| amount_common_from_p50 | false | 0.2 | 0.3 | 7615.8 | 9161.0 | - | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| amount_rare_from_p99 | false | 1.9 | 2.7 | 626.6 | 1023.5 | 6906.6 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| amount_rare_range | false | 8.0 | 8.5 | 558.7 | 523.1 | 3963.4 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| combo_customer_status_date | true | 367.6 | 0.5 | 312.0 | 465.2 | 5876.8 | - | - | - | Index Scan | SLOW |  |
| combo_provider_status | false | 0.2 | 0.2 | 11031.9 | 5853.3 | 48962.4 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| combo_status_amount | false | 0.2 | 0.2 | 2955.6 | 4364.5 | 20840.6 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| combo_status_currency_date | true | 0.1 | 0.1 | 4.6 | 5.6 | 2500.8 | - | - | - | Index Scan |  |  |
| control | false | 0.1 | 0.1 | 14064.9 | 15417.3 | 51394.8 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| control_page50 | false | 3.7 | 3.5 | 15895.7 | 14840.4 | 51379.6 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| created_24m | false | 0.1 | 0.1 | 14547.4 | 14673.2 | - | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| created_7d | true | 0.1 | 0.1 | 10.1 | 9.6 | 2392.3 | - | - | - | Index Scan |  |  |
| currency_common | false | 0.1 | 0.1 | 15144.6 | 14084.0 | 56285.7 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| currency_rare | true | 2.5 | 2.5 | 864.3 | 636.3 | 6290.5 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| customer_heavy | true | 399.4 | 1.8 | 415.7 | 532.8 | 5860.3 | - | - | - | Index Scan | SLOW | COUNT>500 |
| customer_light | true | 1.8 | 0.1 | 1.6 | 0.1 | 2204.5 | - | - | - | Sort, Index Scan |  |  |
| five_filter_common | false | 0.1 | 0.2 | 16647.1 | 9715.4 | - | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| five_filter_rare | true | 20.8 | 18.6 | 21.0 | 18.8 | 1997.5 | - | - | - | Sort, Bitmap Heap Scan, BitmapAnd, Bitmap Index Scan, Index Scan |  |  |
| invoice_hit_direct | true | 72525.3 | 0.0 | 18048.9 | 0.0 | - | - | - | - | Sort, Index Scan | SLOW COUNT>500 SEQ:invoices |  |
| invoice_hit_request | true | 83846.9 | 0.0 | 17075.0 | 0.0 | - | - | - | - | Sort, Bitmap Heap Scan, BitmapOr, Bitmap Index Scan, Index Scan | SLOW COUNT>500 SEQ:invoices |  |
| invoice_miss | true | 60503.3 | 0.0 | 16473.7 | 0.0 | - | - | - | - | Sort, Result | SLOW COUNT>500 SEQ:invoices |  |
| payable_type_invoice | false | 0.1 | 0.1 | 15354.1 | 15783.2 | 54239.9 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| payable_type_request | false | 1.0 | 0.3 | 480.5 | 389.8 | 5076.7 | - | - | - | Index Scan |  |  |
| payment_type_manual | false | 0.7 | 0.3 | 2217.9 | 6287.7 | 26829.8 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| payment_type_provider | false | 0.2 | 0.1 | 12469.5 | 15557.3 | 45414.8 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| provider_common | false | 0.3 | 0.1 | 23420.6 | 12901.0 | - | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| provider_miss | true | 66537.5 | 0.0 | 5.7 | 0.0 | - | - | - | - | Sort, Result | SLOW |  |
| provider_rare | false | 0.5 | 0.1 | 9733.1 | 9222.5 | 46707.1 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| receipt_hit | true | 105274.1 | 0.1 | 282.9 | 0.0 | - | - | - | - | Sort, Nested Loop, Index Scan | SLOW SEQ:payment_receipts |  |
| receipt_miss | true | - | 0.0 | 239.3 | 0.0 | - | - | - | - | Sort, Nested Loop, Index Scan | SLOW SEQ:payment_receipts TIMEOUT |  |
| search_term | true | 56.0 | 52.4 | 52.8 | 56.6 | 2119.3 | - | - | - | Sort, Nested Loop, HashAggregate, Append, Bitmap Heap Scan, Bitmap Index Scan, Index Scan |  |  |
| search_term_status | true | 49.6 | 54.0 | 50.6 | 51.2 | 2913.3 | - | - | - | Sort, Nested Loop, HashAggregate, Append, Bitmap Heap Scan, Bitmap Index Scan, Index Scan |  |  |
| status_common_succeeded | false | 0.1 | 0.1 | 11376.0 | 12473.4 | - | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| status_common_succeeded_page50 | false | 2.3 | 3.8 | 12762.0 | 15925.3 | 50229.5 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| status_rare_failed | false | 0.3 | 0.3 | 3411.5 | 10938.7 | 43340.0 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| status_rare_pending | true | 0.5 | 0.1 | 831.9 | 353.9 | 9685.4 | - | - | - | Index Scan | COUNT>500 |  |
| status_rare_pending_processing | true | 0.3 | 0.5 | 1481.3 | 528.3 | 24907.5 | - | - | - | Index Scan | COUNT>500 | COUNT>500 |
| status_rare_processing | true | 0.5 | 0.1 | 574.2 | 177.2 | 8238.0 | - | - | - | Index Scan | COUNT>500 |  |

## Scoreboard (after)

| # | target | result |
|---|---|---|
| G1 | single filter p95 < 300 ms | n/a (no http bench) |
| G2 | five-filter p95 < 800 ms | n/a (no http bench) |
| G3 | COUNT(*) < 500 ms (selective cases, new filters) | RED worst status_rare_pending_processing 528.3 ms; non-selective worst status_common_succeeded_page50 15925.3 ms and pre-existing filters over 500 ms (currency_common 14084.0 ms, currency_rare 636.3 ms, customer_heavy 532.8 ms) reported separately |
| G4 | control p95 within +10 % | n/a (no http bench on both phases) |
| G5 | selective plans: no watched Seq Scan, no Sort > 10k | GREEN all 18 selective cases clean |
| G8 | zero errors in the load test | n/a (no http bench) |
| G9 | page 50 < 2x page 1 | GREEN control_page50 0.1 -> 3.5 ms; status_common_succeeded_page50 0.1 -> 3.8 ms |

G6 (<= 3 new payments indexes) and G7 (build < 15 min, no INVALID) are graded from the migration run log.
