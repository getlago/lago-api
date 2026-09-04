# frozen_string_literal: true

module Subscriptions
  module ProductCatalog
    # Materializes the plan's rate cards onto the subscription: one subscription_rate_card
    # per plan_rate_card, carrying the billing lifecycle (anchor, clock, units). Pricing is
    # not copied — a plan is immutable once it has subscriptions, so phases and rates
    # resolve by reference through the plan entry.
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
          subscription.plan.applied_rate_cards.find_each do |plan_rate_card|
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
          billing_anchor_date: subscription.effective_billing_anchor_date,
          started_at:
        )
        item.next_billing_at = initial_next_billing_at(item, plan_rate_card)
        item.save!
        item
      end

      # When the clock should first look at this card. A backdated subscription therefore
      # bills the period it lands in today rather than the ones it missed: the gap is
      # deliberate, since back-billing the past on signup would surprise the customer.
      #
      # Without a resolvable rate there is no cadence to schedule on, so fall back to
      # started_at and let a later scheduler pass move the clock on (QA plan R2).
      def initial_next_billing_at(item, plan_rate_card)
        build = Billing::RateCards::BuildScheduleService.call(subscription_rate_card: item, plan_rate_card:)
        return started_at unless build.success?

        build.schedule.next_billing_at(Time.current)
      end

      def started_at
        @started_at ||= subscription.started_at || subscription.subscription_at
      end
    end
  end
end
