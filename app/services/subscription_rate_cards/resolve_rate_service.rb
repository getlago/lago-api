# frozen_string_literal: true

module SubscriptionRateCards
  # Resolves the active rate for a subscription product item at a given moment.
  #
  # The item carries its own rate_card (materialized from the plan, or attached
  # directly for sales-led subscriptions), and the active rate is the latest one whose
  # effective_datetime is on or before `datetime` — RateCard#rate_active_at. Rates are
  # append-only and the card is locked once it has subscriptions, so the subscriber's
  # price is frozen at signing. The rate_phase / rate_override layer plugs in here in v2.
  #
  #   rate_card timeline: $0.10 (eff 2026-01-01), $0.15 (eff 2026-07-01)
  #   resolve at 2026-03-01 => $0.10 ; resolve at 2026-08-01 => $0.15
  class ResolveRateService < BaseService
    Result = BaseResult[:rate]

    def initialize(subscription_rate_card:, datetime:)
      @subscription_rate_card = subscription_rate_card
      @datetime = datetime
      super
    end

    def call
      return result.not_found_failure!(resource: "rate") unless rate

      result.rate = rate
      result
    end

    private

    attr_reader :subscription_rate_card, :datetime

    def rate
      @rate ||= subscription_rate_card.rate_card&.rate_active_at(datetime)
    end
  end
end
