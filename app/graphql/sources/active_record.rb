# frozen_string_literal: true

# This is a reusable, model-agnostic loader for any ID-based ActiveRecord lookup.
#
# Prevents N+1 queries when fetching associated records across multiple objects
# in a single GraphQL query (e.g., `quotes { customer { ... } }`).
#
# Collects all requested IDs and loads the corresponding records in a single query,
# then maps them back to the original order so each object receives its associated record.
#
# Usage in GraphQL types:
#   dataloader.with(Sources::ActiveRecord, Customer).load(object.customer_id)

module Sources
  class ActiveRecord < GraphQL::Dataloader::Source
    def initialize(model)
      @model = model
    end

    def fetch(ids)
      records = @model.where(id: ids).index_by(&:id)
      ids.map { |id| records[id] }
    end
  end
end
