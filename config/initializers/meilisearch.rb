# frozen_string_literal: true

MeiliSearch::Rails.configuration = {
  meilisearch_url: ENV["LAGO_MEILISEARCH_URL"] || "http://localhost:7700",
  meilisearch_api_key: ENV["LAGO_MEILISEARCH_API_KEY"],
  active: ENV["LAGO_MEILISEARCH_URL"].present?,
  # NOTE: suffixes index names with the Rails env (e.g. `invoices_production`)
  per_environment: true,
  pagination_backend: :kaminari
}
