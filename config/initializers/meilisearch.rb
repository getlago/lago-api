# frozen_string_literal: true

require "lago/meilisearch"

if Lago::Meilisearch.enabled?
  Meilisearch::Rails.configuration = {
    meilisearch_url: Lago::Meilisearch.url,
    meilisearch_api_key: Lago::Meilisearch.api_key,
    per_environment: true,
    pagination_backend: :kaminari
  }
end
