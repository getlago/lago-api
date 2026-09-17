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
  class CountByForeignKey < GraphQL::Dataloader::Source
    def initialize(model, foreign_key)
      @model = model
      @foreign_key = foreign_key
    end

    def fetch(ids)
      # reorder(nil) drops any default-scope ordering, which would otherwise
      # leak into the GROUP BY and fail.
      counts = @model.where(@foreign_key => ids).reorder(nil).group(@foreign_key).count

      ids.map { counts.fetch(it, 0) }
    end
  end
end
