# frozen_string_literal: true

# meilisearch-rails configuration.
# When LAGO_MEILISEARCH_URL is blank (e.g. test/CI), `active: false` turns every
# index/search operation into a no-op, so the app behaves as if search is off.
MeiliSearch::Rails.configuration = {
  meilisearch_url: ENV["LAGO_MEILISEARCH_URL"] || "http://localhost:7700",
  meilisearch_api_key: ENV["MEILI_MASTER_KEY"],
  active: ENV["LAGO_MEILISEARCH_URL"].present?,
  per_environment: true,
  pagination_backend: :kaminari
}
