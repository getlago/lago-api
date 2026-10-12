# Plans: after

Median of n (see plan headers) EXPLAIN (ANALYZE, BUFFERS) runs per statement. Synthetic dataset. `ms` is nil when the statement hit the timeout.

| case | page | selective | list ms | count ms | rows | list nodes | seq scan (watched) | max sort rows | shared read (list) | ordering by cursor index | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|
| amount_common_from_p50 | 1 | false | 0.3 | 9161.0 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| amount_rare_from_p99 | 1 | false | 2.7 | 1023.5 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| amount_rare_range | 1 | false | 8.5 | 523.1 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| combo_customer_status_date | 1 | true | 0.5 | 465.2 | 20 | Index Scan |  | 0 | 0 | true |  |
| combo_provider_status | 1 | false | 0.2 | 5853.3 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| combo_status_amount | 1 | false | 0.2 | 4364.5 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| combo_status_currency_date | 1 | true | 0.1 | 5.6 | 20 | Index Scan |  | 0 | 0 | true |  |
| control | 1 | false | 0.1 | 15417.3 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| control_page50 | 50 | false | 3.5 | 14840.4 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| created_24m | 1 | false | 0.1 | 14673.2 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| created_7d | 1 | true | 0.1 | 9.6 | 20 | Index Scan |  | 0 | 0 | true |  |
| currency_common | 1 | false | 0.1 | 14084.0 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| currency_rare | 1 | true | 2.5 | 636.3 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| customer_heavy | 1 | true | 1.8 | 532.8 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| customer_light | 1 | true | 0.1 | 0.1 | 20 | Sort, Index Scan |  | 20 | 0 | false |  |
| five_filter_common | 1 | false | 0.2 | 9715.4 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| five_filter_rare | 1 | true | 18.6 | 18.8 | 0 | Sort, Bitmap Heap Scan, BitmapAnd, Bitmap Index Scan, Index Scan |  | 0 | 0 | false |  |
| invoice_hit_direct | 1 | true | 0.0 | 0.0 | 2 | Sort, Index Scan |  | 2 | 0 | false |  |
| invoice_hit_request | 1 | true | 0.0 | 0.0 | 1 | Sort, Bitmap Heap Scan, BitmapOr, Bitmap Index Scan, Index Scan |  | 1 | 0 | false |  |
| invoice_miss | 1 | true | 0.0 | 0.0 | 0 | Sort, Result |  | 0 |  | false |  |
| payable_type_invoice | 1 | false | 0.1 | 15783.2 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| payable_type_request | 1 | false | 0.3 | 389.8 | 20 | Index Scan |  | 0 | 0 | true |  |
| payment_type_manual | 1 | false | 0.3 | 6287.7 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| payment_type_provider | 1 | false | 0.1 | 15557.3 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| provider_common | 1 | false | 0.1 | 12901.0 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| provider_miss | 1 | true | 0.0 | 0.0 | 0 | Sort, Result |  | 0 |  | false |  |
| provider_rare | 1 | false | 0.1 | 9222.5 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| receipt_hit | 1 | true | 0.1 | 0.0 | 2 | Sort, Nested Loop, Index Scan |  | 2 | 0 | false |  |
| receipt_miss | 1 | true | 0.0 | 0.0 | 0 | Sort, Nested Loop, Index Scan |  | 0 | 0 | false |  |
| search_term | 1 | true | 52.4 | 56.6 | 1 | Sort, Nested Loop, HashAggregate, Append, Bitmap Heap Scan, Bitmap Index Scan, Index Scan |  | 1 | 0 | false |  |
| search_term_status | 1 | true | 54.0 | 51.2 | 1 | Sort, Nested Loop, HashAggregate, Append, Bitmap Heap Scan, Bitmap Index Scan, Index Scan |  | 1 | 0 | false |  |
| status_common_succeeded | 1 | false | 0.1 | 12473.4 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_common_succeeded_page50 | 50 | false | 3.8 | 15925.3 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_rare_failed | 1 | false | 0.3 | 10938.7 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_rare_pending | 1 | true | 0.1 | 353.9 | 20 | Index Scan |  | 0 | 0 | false |  |
| status_rare_pending_processing | 1 | true | 0.5 | 528.3 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_rare_processing | 1 | true | 0.1 | 177.2 | 20 | Index Scan |  | 0 | 0 | false |  |
