# frozen_string_literal: true

MeiliSearch::Rails.configuration = {
  meilisearch_url: ENV["LAGO_MEILISEARCH_URL"] || "http://localhost:7700",
  meilisearch_api_key: ENV["LAGO_MEILISEARCH_MASTER_KEY"],
  active: ENV["LAGO_MEILISEARCH_URL"].present?,
  per_environment: true,
  pagination_backend: :kaminari
}
