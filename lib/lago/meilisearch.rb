# frozen_string_literal: true

module Lago
  module Meilisearch
    # Maximum number of document ids fetched from Meilisearch for a single search.
    # Results are then narrowed down and paginated through ActiveRecord, so this
    # acts as an upper bound on how many text matches a single query can surface.
    SEARCH_RESULT_LIMIT = 1_000

    # Disabled in the test environment so model callbacks never reach a real
    # Meilisearch instance. Specs that exercise the search path stub `enabled?`.
    def self.enabled?
      return false if Rails.env.test?

      ActiveModel::Type::Boolean.new.cast(ENV["LAGO_MEILISEARCH_ENABLED"])
    end

    def self.url
      ENV["LAGO_MEILISEARCH_URL"]
    end

    def self.api_key
      ENV["MEILI_MASTER_KEY"]
    end
  end
end
