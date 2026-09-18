# Load test: after (sql)

20 concurrent clients, 15s per case, synthetic dataset.

| case | selective | requests | req/s | p50 ms | p95 ms | p99 ms | max ms | errors |
|---|---|---|---|---|---|---|---|---|
| control | false | 20 | 1.3 |  |  |  |  | 20 |
| control_page50 | false | 20 | 1.3 |  |  |  |  | 20 |
| status_common_succeeded | false | 20 | 1.3 |  |  |  |  | 20 |
| status_common_succeeded_page50 | false | 20 | 1.3 |  |  |  |  | 20 |
| status_rare_failed | false | 20 | 1.3 | 17941.8 | 17946.1 | 17950.3 | 17950.3 | 0 |
| status_rare_pending | true | 235 | 15.7 | 785.9 | 6378.9 | 6384.0 | 6384.9 | 0 |
| status_rare_processing | true | 596 | 39.7 | 380.5 | 700.8 | 3006.5 | 3007.7 | 0 |
| status_rare_pending_processing | true | 246 | 16.4 | 1091.1 | 1860.5 | 2234.3 | 2262.0 | 0 |
| amount_common_from_p50 | false | 20 | 1.3 |  |  |  |  | 20 |
| amount_rare_from_p99 | false | 189 | 12.6 | 1254.2 | 4979.8 | 4985.2 | 4985.6 | 0 |
| amount_rare_range | false | 266 | 17.7 | 1053.4 | 1805.9 | 2057.6 | 2231.5 | 0 |
| created_7d | true | 12513 | 834.2 | 23.1 | 32.4 | 39.2 | 222.0 | 0 |
| created_24m | false | 20 | 1.3 |  |  |  |  | 20 |
| currency_common | false | 20 | 1.3 |  |  |  |  | 20 |
| currency_rare | true | 196 | 13.1 | 1229.2 | 4373.1 | 4378.3 | 4378.8 | 0 |
| provider_common | false | 20 | 1.3 |  |  |  |  | 20 |
| provider_rare | false | 40 | 2.7 | 14290.5 | 20420.1 | 20420.7 | 20420.7 | 0 |
| provider_miss | true | 28266 | 1884.4 | 10.4 | 11.8 | 14.5 | 24.1 | 0 |
| receipt_hit | true | 26399 | 1759.9 | 11.0 | 14.2 | 18.1 | 34.6 | 0 |
| receipt_miss | true | 26969 | 1797.9 | 10.9 | 12.6 | 15.3 | 35.7 | 0 |
| invoice_hit_direct | true | 27083 | 1805.5 | 10.7 | 13.7 | 16.6 | 31.6 | 0 |
| invoice_hit_request | true | 27472 | 1831.5 | 10.7 | 12.4 | 15.2 | 34.5 | 0 |
| invoice_miss | true | 27913 | 1860.9 | 10.5 | 12.1 | 14.8 | 35.2 | 0 |
| customer_heavy | true | 207 | 13.8 | 1309.8 | 3061.0 | 3090.6 | 3102.2 | 0 |
| customer_light | true | 27024 | 1801.6 | 10.6 | 14.0 | 16.4 | 30.3 | 0 |
| payment_type_manual | false | 40 | 2.7 | 10143.4 | 12971.9 | 12973.6 | 12973.6 | 0 |
| payment_type_provider | false | 84 | 5.6 |  |  |  |  | 84 |
| payable_type_request | false | 289 | 19.3 | 911.9 | 2230.6 | 3097.7 | 3332.7 | 0 |
| payable_type_invoice | false | 20 | 1.3 |  |  |  |  | 20 |
| search_term | true | 1009 | 67.3 | 245.6 | 551.6 | 650.0 | 785.0 | 0 |
| search_term_status | true | 1034 | 68.9 | 231.9 | 546.5 | 664.5 | 762.7 | 0 |
| combo_status_currency_date | true | 14792 | 986.1 | 19.6 | 27.0 | 31.5 | 227.7 | 0 |
| combo_status_amount | false | 40 | 2.7 | 12505.7 | 14061.5 | 14062.4 | 14062.4 | 0 |
| combo_customer_status_date | true | 259 | 17.3 | 1077.2 | 1811.1 | 2029.4 | 2194.4 | 0 |
| combo_provider_status | false | 20 | 1.3 | 17969.2 | 17971.2 | 17971.5 | 17971.5 | 0 |
| five_filter_common | false | 20 | 1.3 |  |  |  |  | 20 |
| five_filter_rare | true | 2636 | 175.7 | 105.0 | 193.2 | 245.7 | 435.3 | 0 |
