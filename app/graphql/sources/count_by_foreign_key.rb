# frozen_string_literal: true

module Sources
  # Batches per-row COUNT fields into a single grouped query.
  #
  # Prevents N+1 queries when a count is requested for several parent records
  # in one GraphQL query (e.g., `products { filtersCount }`). The model's
  # default scope applies, so soft-deleted rows stay excluded exactly as in
  # the per-record `association.count`.
  #
  # Usage in GraphQL types:
  #   dataloader.with(Sources::CountByForeignKey, ProductFilter, :product_id).load(object.id)
  #   dataloader.with(Sources::CountByForeignKey, Contract, :catalog_plan_id, :not_canceled).load(object.id)
  #
  # The optional scope is the name of a model scope: a symbol keeps the batch key stable,
  # where a relation would open one batch per call.
  class CountByForeignKey < GraphQL::Dataloader::Source
    def initialize(model, foreign_key, scope = nil)
      @model = model
      @foreign_key = foreign_key
      @scope = scope
    end

    def fetch(ids)
      relation = @scope ? @model.public_send(@scope) : @model
      # reorder(nil) drops any default-scope ordering, which would otherwise
      # leak into the GROUP BY and fail.
      counts = relation.where(@foreign_key => ids).reorder(nil).group(@foreign_key).count

      ids.map { counts.fetch(it, 0) }
    end
  end
end
