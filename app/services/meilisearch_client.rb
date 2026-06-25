# frozen_string_literal: true

# Gating predicate for invoice search indexing/querying.
#
# Indexing and search settings live in the model's `meilisearch do … end` block
# (see Invoice); this only answers "is Meilisearch configured for this env?".
class MeilisearchClient
  def self.enabled?
    ENV["LAGO_MEILISEARCH_URL"].present?
  end
end
