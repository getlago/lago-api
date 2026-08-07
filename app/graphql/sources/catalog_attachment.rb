# frozen_string_literal: true

module Sources
  # Batches attached_to_plan_or_subscription? across catalog rows: one grouped
  # query per applied-card side instead of two EXISTS per row.
  #
  # Keyed by the grouping the caller resolves through — a product id for
  # products and their filters (a filter is attached when its product is), a
  # product_category id for categories (attached through their products).
  # Default scopes apply on both the applied cards and the joined models, so
  # discarded rows stay excluded exactly as in the per-record checks.
  #
  # Usage in GraphQL types:
  #   dataloader.with(Sources::CatalogAttachment, :product).load(object.id)
  class CatalogAttachment < GraphQL::Dataloader::Source
    GROUPINGS = {
      product: [:rate_card, "rate_cards.product_id"],
      product_category: [{rate_card: :product}, "products.product_category_id"]
    }.freeze

    def initialize(group_by)
      @joins, @column = GROUPINGS.fetch(group_by)
    end

    def fetch(ids)
      attached = PlanRateCard.joins(@joins).where(@column => ids).distinct.pluck(Arel.sql(@column)) |
        SubscriptionRateCard.joins(@joins).where(@column => ids).distinct.pluck(Arel.sql(@column))

      ids.map { attached.include?(it) }
    end
  end
end
