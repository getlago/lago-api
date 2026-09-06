# frozen_string_literal: true

# Vendored verbatim from app/services/subscription_rate_cards/resolve_rate_phases_service.rb on PR getlago/lago-api#6267
# (branch `engine-dates`). Do not edit: this is the frozen PR engine. Only the outermost
# module and the cross-namespace constant references are re-rooted under `PrEngine::`;
# every method body is the PR's own.
module PrEngine; end

module PrEngine::SubscriptionRateCards
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

    def call
      result.rate_phases = phases
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
