# frozen_string_literal: true

module Lago
  # Gating predicates for invoice search indexing/querying.
  #
  # Indexing and search settings live in the model's `meilisearch do … end` block
  # (see Invoice).
  #
  # - `indexing_enabled?` answers "is Meilisearch configured for this env?" and
  #   gates indexing (writing documents to the index).
  # - `search_enabled?` additionally requires `LAGO_MEILISEARCH_SEARCH_ENABLED`
  #   and gates the query/read path. Keeping it separate lets the index be
  #   populated or reindexed without impacting user search results until the
  #   flag is flipped.
  #
  # Namespaced under Lago:: to avoid clashing with the gem's top-level
  # `Meilisearch` constant.
  module Meilisearch
    def self.indexing_enabled?
      ENV["LAGO_MEILISEARCH_URL"].present?
    end

    def self.search_enabled?
      indexing_enabled? && ActiveModel::Type::Boolean.new.cast(ENV["LAGO_MEILISEARCH_SEARCH_ENABLED"])
    end
  end
end
