# frozen_string_literal: true

module SubscriptionRateCards
  # Detaches a rate card from a subscription during the authoring window: only
  # while the subscription is pending — once active, its pricing is signed.
  class DestroyService < BaseService
    Result = BaseResult[:subscription_rate_card]

    def initialize(subscription_rate_card:)
      @subscription_rate_card = subscription_rate_card
      super
    end

    def call
      return result.not_found_failure!(resource: "subscription_rate_card") unless subscription_rate_card

      unless subscription_rate_card.subscription.pending?
        return result.single_validation_failure!(field: :subscription, error_code: "subscription_locked")
      end

      ActiveRecord::Base.transaction do
        phases = subscription_rate_card.rate_phases.to_a
        RateOverride.where(id: phases.filter_map(&:rate_override_id)).discard_all!
        subscription_rate_card.rate_phases.discard_all!
        subscription_rate_card.discard!
      end

      result.subscription_rate_card = subscription_rate_card
      result
    end

    private

    attr_reader :subscription_rate_card
  end
end
