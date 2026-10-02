# Plans: baseline

Median of n (see plan headers) EXPLAIN (ANALYZE, BUFFERS) runs per statement. Synthetic dataset. `ms` is nil when the statement hit the timeout.

| case | page | selective | list ms | count ms | rows | list nodes | seq scan (watched) | max sort rows | shared read (list) | ordering by cursor index | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|
| amount_common_from_p50 | 1 | false | 0.2 | 7615.8 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| amount_rare_from_p99 | 1 | false | 1.9 | 626.6 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| amount_rare_range | 1 | false | 8.0 | 558.7 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| combo_customer_status_date | 1 | true | 367.6 | 312.0 | 20 | Sort, Nested Loop, Index Scan |  | 20 | 0 | false | SLOW |
| combo_provider_status | 1 | false | 0.2 | 11031.9 | 20 | Nested Loop, Index Scan |  | 0 | 0 | true | COUNT>500 |
| combo_status_amount | 1 | false | 0.2 | 2955.6 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| combo_status_currency_date | 1 | true | 0.1 | 4.6 | 20 | Index Scan |  | 0 | 0 | true |  |
| control | 1 | false | 0.1 | 14064.9 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| control_page50 | 50 | false | 3.7 | 15895.7 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| created_24m | 1 | false | 0.1 | 14547.4 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| created_7d | 1 | true | 0.1 | 10.1 | 20 | Index Scan |  | 0 | 0 | true |  |
| currency_common | 1 | false | 0.1 | 15144.6 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| currency_rare | 1 | true | 2.5 | 864.3 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| customer_heavy | 1 | true | 399.4 | 415.7 | 20 | Sort, Nested Loop, Index Scan |  | 20 | 0 | false | SLOW |
| customer_light | 1 | true | 1.8 | 1.6 | 20 | Sort, Nested Loop, Index Scan |  | 20 | 0 | false |  |
| five_filter_common | 1 | false | 0.1 | 16647.1 | 20 | Nested Loop, Index Scan, Memoize |  | 0 | 0 | true | COUNT>500 |
| five_filter_rare | 1 | true | 20.8 | 21.0 | 0 | Sort, Nested Loop, Seq Scan, Bitmap Heap Scan, BitmapAnd, Bitmap Index Scan, Index Scan |  | 0 | 0 | false |  |
| invoice_hit_direct | 1 | true | 72525.3 | 18048.9 | 2 | Nested Loop Semi Join, Index Scan, Materialize, Gather, Parallel Seq Scan, Seq Scan | invoices | 0 | 3070314 | true | SLOW COUNT>500 SEQ:invoices |
| invoice_hit_request | 1 | true | 83846.9 | 17075.0 | 1 | Nested Loop Semi Join, Index Scan, Materialize, Gather, Parallel Seq Scan, Seq Scan | invoices | 0 | 3070354 | true | SLOW COUNT>500 SEQ:invoices |
| invoice_miss | 1 | true | 60503.3 | 16473.7 | 0 | Nested Loop Semi Join, Index Scan, Materialize, Gather, Parallel Seq Scan, Seq Scan | invoices | 0 | 3067056 | true | SLOW COUNT>500 SEQ:invoices |
| method_common_json | 1 | false | 0.2 | 14714.5 | 20 | Nested Loop Left Join, Index Scan |  | 0 | 0 | true | COUNT>500 |
| method_fallback_only | 1 | true | 37.4 | 14751.8 | 20 | Nested Loop Left Join, Index Scan |  | 0 | 0 | true | COUNT>500 |
| method_multi | 1 | false | 0.1 | 16669.8 | 20 | Nested Loop Left Join, Index Scan |  | 0 | 0 | true | COUNT>500 |
| method_rare_json | 1 | true | 145.1 | 19374.8 | 20 | Nested Loop Left Join, Index Scan |  | 0 | 0 | true | COUNT>500 |
| payable_type_invoice | 1 | false | 0.1 | 15354.1 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| payable_type_request | 1 | false | 1.0 | 480.5 | 20 | Index Scan |  | 0 | 0 | true |  |
| payment_type_manual | 1 | false | 0.7 | 2217.9 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| payment_type_provider | 1 | false | 0.2 | 12469.5 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| provider_common | 1 | false | 0.3 | 23420.6 | 20 | Nested Loop, Index Scan, Memoize |  | 0 | 0 | true | COUNT>500 |
| provider_miss | 1 | true | 66537.5 | 5.7 | 0 | Nested Loop, Index Scan, Materialize, Seq Scan |  | 0 | 2937644 | true | SLOW |
| provider_rare | 1 | false | 0.5 | 9733.1 | 20 | Nested Loop, Index Scan, Memoize |  | 0 | 0 | true | COUNT>500 |
| receipt_hit | 1 | true | 105274.1 | 282.9 | 2 | Nested Loop, Index Scan | payment_receipts | 0 | 4564673 | true | SLOW SEQ:payment_receipts |
| receipt_miss | 1 | true | timeout | 239.3 | 0 |  | payment_receipts | 0 |  | false | SLOW SEQ:payment_receipts TIMEOUT |
| search_term | 1 | true | 56.0 | 52.8 | 1 | Sort, Nested Loop, HashAggregate, Append, Bitmap Heap Scan, Bitmap Index Scan, Index Scan |  | 1 | 0 | false |  |
| search_term_status | 1 | true | 49.6 | 50.6 | 1 | Sort, Nested Loop, HashAggregate, Append, Bitmap Heap Scan, Bitmap Index Scan, Index Scan |  | 1 | 0 | false |  |
| status_common_succeeded | 1 | false | 0.1 | 11376.0 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_common_succeeded_page50 | 50 | false | 2.3 | 12762.0 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_rare_failed | 1 | false | 0.3 | 3411.5 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_rare_pending | 1 | true | 0.5 | 831.9 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_rare_pending_processing | 1 | true | 0.3 | 1481.3 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
| status_rare_processing | 1 | true | 0.5 | 574.2 | 20 | Index Scan |  | 0 | 0 | true | COUNT>500 |
