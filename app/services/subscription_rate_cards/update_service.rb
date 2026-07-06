# frozen_string_literal: true

module SubscriptionRateCards
  # Edits a subscription entry during the authoring window: only while the
  # subscription is pending — once active, its pricing is signed.
  class UpdateService < BaseService
    Result = BaseResult[:subscription_rate_card]

    def initialize(subscription_rate_card:, params:)
      @subscription_rate_card = subscription_rate_card
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "subscription_rate_card") unless subscription_rate_card

      unless subscription_rate_card.subscription.pending?
        return result.single_validation_failure!(field: :subscription, error_code: "subscription_locked")
      end

      subscription_rate_card.units = params[:units] if params.key?(:units)
      subscription_rate_card.billing_anchor_date = params[:billing_anchor_date] if params.key?(:billing_anchor_date)

      # The billing clock is seeded from the start date, so it follows it.
      if params.key?(:started_at)
        subscription_rate_card.started_at = params[:started_at]
        subscription_rate_card.next_billing_at = params[:started_at]
      end

      subscription_rate_card.save!

      result.subscription_rate_card = subscription_rate_card
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription_rate_card, :params
  end
end
