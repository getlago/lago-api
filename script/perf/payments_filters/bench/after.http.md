# Load test: after (http)

20 concurrent clients, 30s per case, synthetic dataset.

| case | selective | requests | req/s | p50 ms | p95 ms | p99 ms | max ms | errors |
|---|---|---|---|---|---|---|---|---|
| control | false | 20 | 0.7 |  |  |  |  | 20 |
| control_page50 | false | 20 | 0.7 | 48240.9 | 48240.9 | 48240.9 | 48240.9 | 19 |
| status_common_succeeded | false | 20 | 0.7 |  |  |  |  | 20 |
| status_common_succeeded_page50 | false | 20 | 0.7 | 46098.2 | 46098.2 | 46098.2 | 46098.2 | 19 |
| status_rare_failed | false | 39 | 1.3 | 18238.5 | 33977.9 | 35132.2 | 35132.2 | 0 |
| status_rare_pending | true | 244 | 8.1 | 2235.8 | 5887.5 | 5921.7 | 5924.1 | 0 |
| status_rare_processing | true | 294 | 9.8 | 1855.6 | 4431.9 | 4466.9 | 4470.0 | 0 |
| status_rare_pending_processing | true | 252 | 8.4 | 2513.1 | 3246.7 | 3713.5 | 5027.2 | 0 |
| amount_common_from_p50 | false | 20 | 0.7 | 31208.0 | 31256.3 | 31257.5 | 31257.5 | 0 |
| amount_rare_from_p99 | false | 209 | 7.0 | 2567.7 | 6089.1 | 6127.1 | 8259.8 | 0 |
| amount_rare_range | false | 263 | 8.8 | 2333.8 | 3102.6 | 3985.1 | 4577.7 | 0 |
| created_7d | true | 341 | 11.4 | 1768.6 | 2435.5 | 2812.2 | 3088.1 | 0 |
| created_24m | false | 20 | 0.7 |  |  |  |  | 20 |
| currency_common | false | 20 | 0.7 |  |  |  |  | 20 |
| currency_rare | true | 206 | 6.9 | 2667.8 | 5648.0 | 5684.3 | 5689.5 | 0 |
| provider_common | false | 20 | 0.7 |  |  |  |  | 20 |
| provider_rare | true | 39 | 1.3 | 18893.8 | 32078.4 | 34350.3 | 34350.3 | 0 |
| provider_miss | true | 392 | 13.1 | 1515.6 | 1962.6 | 2572.6 | 2952.8 | 0 |
| receipt_hit | true | 384 | 12.8 | 1554.9 | 1898.9 | 2462.3 | 2847.2 | 0 |
| receipt_miss | true | 359 | 12.0 | 1560.7 | 2649.9 | 3830.3 | 4331.2 | 0 |
| invoice_hit_direct | true | 378 | 12.6 | 1552.0 | 2095.4 | 2566.2 | 2996.9 | 0 |
| invoice_hit_request | true | 384 | 12.8 | 1553.9 | 2018.9 | 2267.7 | 2434.8 | 0 |
| invoice_miss | true | 404 | 13.5 | 1499.2 | 1810.9 | 2447.0 | 2734.4 | 0 |
| customer_heavy | true | 215 | 7.2 | 2641.9 | 4289.4 | 5381.0 | 6165.6 | 0 |
| customer_light | true | 352 | 11.7 | 1723.1 | 2112.5 | 2458.0 | 2774.7 | 0 |
| payment_type_manual | false | 56 | 1.9 | 11503.1 | 22119.8 | 22122.4 | 22122.4 | 0 |
| payment_type_provider | false | 20 | 0.7 | 48484.3 | 48484.3 | 48484.3 | 48484.3 | 19 |
| payable_type_request | false | 248 | 8.3 | 2274.6 | 4251.5 | 4578.1 | 4613.8 | 0 |
| payable_type_invoice | false | 40 | 1.3 |  |  |  |  | 40 |
| search_term | true | 362 | 12.1 | 1639.2 | 2517.3 | 3282.0 | 3528.1 | 0 |
| search_term_status | true | 363 | 12.1 | 1622.4 | 2052.3 | 2977.3 | 3164.3 | 0 |
| combo_status_currency_date | true | 347 | 11.6 | 1745.4 | 2168.6 | 3039.4 | 3281.9 | 0 |
| combo_status_amount | false | 55 | 1.8 | 14607.1 | 28787.9 | 28790.7 | 28790.7 | 0 |
| combo_customer_status_date | true | 246 | 8.2 | 2335.7 | 3668.6 | 4595.2 | 6103.9 | 0 |
| combo_provider_status | false | 40 | 1.3 | 18771.0 | 29351.3 | 29357.7 | 29357.7 | 0 |
| five_filter_common | false | 20 | 0.7 |  |  |  |  | 20 |
| five_filter_rare | true | 384 | 12.8 | 1561.0 | 1968.2 | 2674.6 | 2964.3 | 0 |
