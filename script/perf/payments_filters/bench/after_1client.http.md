# Load test: after_1client (http)

1 concurrent clients, 15s per case, synthetic dataset.

| case | selective | requests | req/s | p50 ms | p95 ms | p99 ms | max ms | errors |
|---|---|---|---|---|---|---|---|---|
| control | false | 1 | 0.1 | 21086.2 | 21086.2 | 21086.2 | 21086.2 | 0 |
| control_page50 | false | 2 | 0.1 | 13621.1 | 13676.5 | 13676.5 | 13676.5 | 0 |
| status_common_succeeded | false | 2 | 0.1 | 10877.7 | 10992.5 | 10992.5 | 10992.5 | 0 |
| status_common_succeeded_page50 | false | 2 | 0.1 | 11234.8 | 12210.8 | 12210.8 | 12210.8 | 0 |
| status_rare_failed | false | 3 | 0.2 | 6159.2 | 7273.0 | 7273.0 | 7273.0 | 0 |
| status_rare_pending | true | 23 | 1.5 | 498.0 | 889.2 | 3177.8 | 3177.8 | 0 |
| status_rare_processing | true | 40 | 2.7 | 339.3 | 438.8 | 1945.1 | 1945.1 | 0 |
| status_rare_pending_processing | true | 24 | 1.6 | 624.6 | 695.3 | 859.0 | 859.0 | 0 |
| amount_common_from_p50 | false | 2 | 0.1 | 7283.9 | 14594.9 | 14594.9 | 14594.9 | 0 |
| amount_rare_from_p99 | false | 18 | 1.2 | 741.4 | 1700.0 | 1700.0 | 1700.0 | 0 |
| amount_rare_range | false | 20 | 1.3 | 738.6 | 807.5 | 989.2 | 989.2 | 0 |
| created_7d | true | 78 | 5.2 | 187.8 | 223.4 | 322.1 | 322.1 | 0 |
| created_24m | false | 1 | 0.1 | 23804.0 | 23804.0 | 23804.0 | 23804.0 | 0 |
| currency_common | false | 2 | 0.1 | 12793.4 | 13373.0 | 13373.0 | 13373.0 | 0 |
| currency_rare | true | 18 | 1.2 | 753.1 | 1489.3 | 1489.3 | 1489.3 | 0 |
| provider_common | false | 1 | 0.1 | 21034.6 | 21034.6 | 21034.6 | 21034.6 | 0 |
| provider_rare | false | 3 | 0.2 | 5839.5 | 6801.4 | 6801.4 | 6801.4 | 0 |
| provider_miss | true | 97 | 6.5 | 151.9 | 182.1 | 209.2 | 209.2 | 0 |
| receipt_hit | true | 94 | 6.3 | 156.1 | 185.0 | 209.2 | 209.2 | 0 |
| receipt_miss | true | 98 | 6.5 | 150.0 | 168.5 | 231.4 | 231.4 | 0 |
| invoice_hit_direct | true | 96 | 6.4 | 154.6 | 178.4 | 206.4 | 206.4 | 0 |
| invoice_hit_request | true | 95 | 6.3 | 156.0 | 189.8 | 216.5 | 216.5 | 0 |
| invoice_miss | true | 100 | 6.7 | 148.2 | 178.6 | 204.8 | 332.4 | 0 |
| customer_heavy | true | 19 | 1.3 | 702.0 | 2518.2 | 2518.2 | 2518.2 | 0 |
| customer_light | true | 87 | 5.8 | 172.1 | 193.6 | 225.5 | 225.5 | 0 |
| payment_type_manual | false | 4 | 0.3 | 3205.0 | 5611.6 | 5611.6 | 5611.6 | 0 |
| payment_type_provider | false | 1 | 0.1 | 19388.5 | 19388.5 | 19388.5 | 19388.5 | 0 |
| payable_type_request | false | 24 | 1.6 | 573.4 | 994.2 | 1374.9 | 1374.9 | 0 |
| payable_type_invoice | false | 1 | 0.1 | 23866.8 | 23866.8 | 23866.8 | 23866.8 | 0 |
| search_term | true | 54 | 3.6 | 273.0 | 324.9 | 331.8 | 331.8 | 0 |
| search_term_status | true | 55 | 3.7 | 266.5 | 314.9 | 320.7 | 320.7 | 0 |
| combo_status_currency_date | true | 80 | 5.3 | 184.6 | 207.7 | 282.9 | 282.9 | 0 |
| combo_status_amount | false | 4 | 0.3 | 3931.4 | 4111.0 | 4111.0 | 4111.0 | 0 |
| combo_customer_status_date | true | 22 | 1.5 | 665.2 | 800.0 | 1077.1 | 1077.1 | 0 |
| combo_provider_status | false | 3 | 0.2 | 5611.8 | 6869.1 | 6869.1 | 6869.1 | 0 |
| five_filter_common | false | 2 | 0.1 | 11442.1 | 12911.2 | 12911.2 | 12911.2 | 0 |
| five_filter_rare | true | 76 | 5.1 | 194.3 | 222.8 | 241.0 | 241.0 | 0 |
