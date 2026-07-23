# frozen_string_literal: true

module Subscriptions
  module ProductCatalog
    # Materializes the plan's rate cards onto the subscription: one
    # subscription_rate_card per plan_rate_card, carrying the billing
    # lifecycle (anchor, clock, units). Pricing is not copied — a plan is
    # immutable once it has subscriptions, so phases and rates resolve by
    # reference through the plan entry.
    #
    # next_billing_at is seeded through FirstPeriodService, which clamps the first
    # period to max(started_at, now): a backdated start bills the current period
    # forward instead of back-billing the missed ones (parity with the legacy engine).
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
            materialized << materialize(plan_rate_card)
          end
        end

        result.subscription_rate_cards = materialized
        result
      end

      private

      attr_reader :subscription

      def materialize(plan_rate_card)
        item = SubscriptionRateCard.new(
          organization: subscription.organization,
          subscription:,
          customer: subscription.customer,
          rate_card: plan_rate_card.rate_card,
          units: plan_rate_card.units,
          billing_anchor_date: started_at.to_date,
          started_at:
        )
        item.next_billing_at = initial_next_billing_at(item)
        item.save!
        item
      end

      # The rate at signing sets the interval/timing FirstPeriodService needs. Without a
      # resolvable rate there is no boundary to compute, so fall back to started_at and
      # let a later scheduler pass advance the clock once the catalog resolves.
      def initial_next_billing_at(item)
        rate = item.rate_card&.rate_active_at(started_at)
        return started_at unless rate

        BillingPeriods::FirstPeriodService
          .from_subscription_rate_card(item, rate:)
          .next_billing_at
      end

      def started_at
        @started_at ||= subscription.started_at || subscription.subscription_at
      end
    end
  end
end
