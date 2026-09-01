# frozen_string_literal: true

module SubscriptionRateCards
  # Which rate phases apply to one card, in the order they are billed in. Phases live on the
  # card once it has its own, and on the plan entry it was materialized from until then —
  # never both at once, so the card's set wins whole rather than merging.
  class ResolveRatePhasesService < BaseService
    Result = BaseResult[:rate_phases]

    # `plan_rate_card` is the plan entry this card was materialized from, or nil when the
    # card is not on a plan. A caller holding many of them picks the matching one itself:
    # batching is its concern, not this service's.
    def initialize(subscription_rate_card:, plan_rate_card: nil)
      @subscription_rate_card = subscription_rate_card
      @plan_rate_card = plan_rate_card
      super
    end

    # Sorted here rather than relied on: both associations happen to order by position
    # today, but Billing::RateCards::Schedule walks the list in the order it is handed and a Phase
    # carries no position to sort by, so the guarantee has to be made once, on the way out.
    def call
      result.rate_phases = phases.sort_by(&:position)
      result
    end

    private

    attr_reader :subscription_rate_card, :plan_rate_card

    def phases
      subscription_phases = subscription_rate_card.rate_phases.to_a
      return subscription_phases if subscription_phases.any?

      plan_rate_card&.rate_phases.to_a
    end
  end
end
