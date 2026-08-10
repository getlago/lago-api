# frozen_string_literal: true

module SubscriptionRateCards
  class ResolveRatePhasesService < BaseService
    Result = BaseResult[:rate_phases]

    RatePhases = Data.define(:phases) do
      def rate_phase_for_cycle(cycle_index)
        cursor = 0

        phases.each do |phase|
          count = phase.billing_interval_cycle_count
          return phase if count.nil?

          cursor += count
          return phase if cycle_index < cursor
        end

        nil
      end
    end

    def initialize(subscription_rate_card:, plan_rate_cards: [])
      @subscription_rate_card = subscription_rate_card
      @plan_rate_cards = plan_rate_cards
      super
    end

    def call
      result.rate_phases = RatePhases.new(phases: phases.sort_by(&:position))
      result
    end

    private

    attr_reader :subscription_rate_card, :plan_rate_cards

    def phases
      subscription_phases = subscription_rate_card.rate_phases.to_a
      return subscription_phases if subscription_phases.any?

      plan_rate_card&.rate_phases.to_a
    end

    def plan_rate_card
      plan_rate_cards.find do |applied_rate_card|
        applied_rate_card.rate_card_id == subscription_rate_card.rate_card_id
      end
    end
  end
end
