# frozen_string_literal: true

module Subscriptions
  module ProductCatalog
    # Materializes the plan's rate cards onto the subscription: one
    # subscription_rate_card per plan_rate_card, carrying the billing
    # lifecycle (anchor, clock, units). Pricing is not copied — a plan is
    # immutable once it has subscriptions, so phases and rates resolve by
    # reference through the plan entry.
    class MaterializeService < BaseService
      Result = BaseResult[:subscription_rate_cards]

      def initialize(subscription:)
        @subscription = subscription
        super
      end

      def call
        return result unless subscription.plan.product_catalog?

        materialized = []
        ActiveRecord::Base.transaction do
          subscription.plan.plan_rate_cards.find_each do |plan_rate_card|
            materialized << SubscriptionRateCard.create!(
              organization: subscription.organization,
              subscription:,
              rate_card: plan_rate_card.rate_card,
              units: plan_rate_card.units,
              billing_anchor_date: started_at.to_date,
              next_billing_at: started_at,
              started_at:
            )
          end
        end

        result.subscription_rate_cards = materialized
        result
      end

      private

      attr_reader :subscription

      def started_at
        @started_at ||= subscription.started_at || subscription.subscription_at
      end
    end
  end
end
