# Load test: baseline (http)

20 concurrent clients, 30s per case, synthetic dataset.

| case | selective | requests | req/s | p50 ms | p95 ms | p99 ms | max ms | errors |
|---|---|---|---|---|---|---|---|---|
| control | false | 20 | 0.7 | 51394.8 | 51394.8 | 51394.8 | 51394.8 | 19 |
| control_page50 | false | 20 | 0.7 | 51379.6 | 51379.6 | 51379.6 | 51379.6 | 19 |
| status_common_succeeded | false | 20 | 0.7 |  |  |  |  | 20 |
| status_common_succeeded_page50 | false | 20 | 0.7 | 50229.5 | 50229.5 | 50229.5 | 50229.5 | 19 |
| status_rare_failed | true | 40 | 1.3 | 22334.2 | 43340.0 | 43353.1 | 43353.1 | 0 |
| status_rare_pending | true | 166 | 5.5 | 2646.4 | 9685.4 | 12945.7 | 12952.4 | 0 |
| status_rare_processing | true | 179 | 6.0 | 2675.2 | 8238.0 | 8259.4 | 8259.8 | 0 |
| status_rare_pending_processing | true | 57 | 1.9 | 12532.6 | 24907.5 | 24924.9 | 24924.9 | 0 |
| amount_common_from_p50 | false | 20 | 0.7 |  |  |  |  | 20 |
| amount_rare_from_p99 | true | 193 | 6.4 | 2661.7 | 6906.6 | 6951.5 | 6952.2 | 0 |
| amount_rare_range | true | 233 | 7.8 | 2578.0 | 3963.4 | 4773.6 | 5082.0 | 0 |
| created_7d | true | 334 | 11.1 | 1783.3 | 2392.3 | 3128.2 | 3563.3 | 0 |
| created_24m | false | 20 | 0.7 |  |  |  |  | 20 |
| currency_common | false | 20 | 0.7 | 56284.2 | 56285.7 | 56285.7 | 56285.7 | 17 |
| currency_rare | true | 203 | 6.8 | 2654.2 | 6290.5 | 6324.0 | 8610.6 | 0 |
| provider_common | false | 20 | 0.7 |  |  |  |  | 20 |
| provider_rare | true | 39 | 1.3 | 25634.5 | 46707.1 | 47897.0 | 47897.0 | 0 |
| provider_miss | true | 20 | 0.7 |  |  |  |  | 20 |
| method_common_json | false | 20 | 0.7 |  |  |  |  | 20 |
| method_rare_json | true | 20 | 0.7 |  |  |  |  | 20 |
| method_fallback_only | true | 20 | 0.7 |  |  |  |  | 20 |
| method_multi | false | 20 | 0.7 |  |  |  |  | 20 |
| receipt_hit | true | 20 | 0.7 |  |  |  |  | 20 |
| receipt_miss | true | 20 | 0.7 |  |  |  |  | 20 |
| invoice_hit_direct | true | 40 | 1.3 |  |  |  |  | 40 |
| invoice_hit_request | true | 38 | 1.3 |  |  |  |  | 38 |
| invoice_miss | true | 20 | 0.7 |  |  |  |  | 20 |
| customer_heavy | true | 153 | 5.1 | 3873.6 | 5860.3 | 7430.9 | 9444.4 | 0 |
| customer_light | true | 346 | 11.5 | 1752.6 | 2204.5 | 2874.6 | 3060.5 | 0 |
| payment_type_manual | false | 40 | 1.3 | 17043.7 | 26829.8 | 26834.8 | 26834.8 | 0 |
| payment_type_provider | false | 20 | 0.7 | 45414.8 | 45414.8 | 45414.8 | 45414.8 | 19 |
| payable_type_request | false | 212 | 7.1 | 2636.1 | 5076.7 | 5145.7 | 5251.2 | 0 |
| payable_type_invoice | false | 20 | 0.7 | 54239.9 | 54239.9 | 54239.9 | 54239.9 | 19 |
| search_term | true | 351 | 11.7 | 1701.7 | 2119.3 | 3074.3 | 3368.8 | 0 |
| search_term_status | true | 344 | 11.5 | 1749.4 | 2913.3 | 3283.3 | 3425.2 | 0 |
| combo_status_currency_date | true | 333 | 11.1 | 1790.3 | 2500.8 | 3386.7 | 3729.3 | 0 |
| combo_status_amount | true | 40 | 1.3 | 20788.9 | 20840.6 | 27367.6 | 27367.6 | 0 |
| combo_customer_status_date | true | 170 | 5.7 | 3332.2 | 5876.8 | 6887.4 | 7350.1 | 0 |
| combo_provider_status | true | 20 | 0.7 | 48962.4 | 48962.4 | 48962.4 | 48962.4 | 19 |
| five_filter_common | false | 20 | 0.7 |  |  |  |  | 20 |
| five_filter_rare | true | 365 | 12.2 | 1606.9 | 1997.5 | 2920.0 | 3026.0 | 0 |
