# frozen_string_literal: true

# Backstop for paths without the /api/v1 page size check (v2 fallback, GraphQL).
# It must stay well above internal batch sizes (BillableMetrics::Aggregations::CustomService uses 1000).
Kaminari.configure { |config| config.max_per_page = 100_000 }
