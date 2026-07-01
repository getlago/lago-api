# frozen_string_literal: true

# Gating predicates for invoice search indexing/querying.
#
# Indexing and search settings live in the model's `meilisearch do … end` block
# (see Invoice).
#
# - `enabled?` answers "is Meilisearch configured for this env?" and gates
#   indexing (writing documents to the index).
# - `search_enabled?` additionally requires `LAGO_USE_MEILISEARCH` and gates the
#   query/read path. Keeping it separate lets the index be populated or
#   reindexed without impacting user search results until the flag is flipped.
class MeilisearchClient
  def self.enabled?
    ENV["LAGO_MEILISEARCH_URL"].present?
  end

  def self.search_enabled?
    enabled? && ActiveModel::Type::Boolean.new.cast(ENV["LAGO_USE_MEILISEARCH"])
  end
end
