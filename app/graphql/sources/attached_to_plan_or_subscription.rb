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
  #   dataloader.with(Sources::AttachedToPlanOrSubscription, :product).load(object.id)
  class AttachedToPlanOrSubscription < GraphQL::Dataloader::Source
    GROUPINGS = {
      product: [:rate_card, "rate_cards.product_id"],
      product_category: [{rate_card: :product}, "products.product_category_id"],
      # The applied tables carry rate_card_id directly, no join needed.
      rate_card: [nil, "rate_card_id"]
    }.freeze

    def initialize(group_by)
      @joins, @column = GROUPINGS.fetch(group_by)
    end

    def fetch(ids)
      attached = grouped_ids(PlanRateCard, ids) | grouped_ids(ContractRateCard, ids)

      ids.map { attached.include?(it) }
    end

    private

    def grouped_ids(model, ids)
      scope = @joins ? model.joins(@joins) : model.all
      scope.where(@column => ids).distinct.pluck(Arel.sql(@column))
    end
  end
end
