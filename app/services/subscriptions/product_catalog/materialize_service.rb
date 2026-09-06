# frozen_string_literal: true

module Subscriptions
  module ProductCatalog
    # Materializes the plan's rate cards onto the subscription: one
    # subscription_rate_card per plan_rate_card, carrying the billing
    # lifecycle (anchor, clock, units). Pricing is not copied — a plan is
    # immutable once it has subscriptions, so phases and rates resolve by
    # reference through the plan entry.
    #
    # next_billing_at is seeded from the card's own schedule: the next instant a segment
    # falls due after now. A backdated start therefore does not back-bill the periods it
    # missed — the clock opens on the first thing still owed.
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

      # The card's own schedule says when it first owes something: the next instant a
      # segment falls due after now. Phases and rate changes are part of that answer, which
      # is why the whole schedule is built rather than one interval read off one rate.
      #
      # Without a resolvable rate there is no boundary to compute, so fall back to
      # started_at and let a later scheduler pass advance the clock once the catalog
      # resolves.
      def initial_next_billing_at(item, plan_rate_card)
        build = ::Billing::BuildScheduleService.call(subscription_rate_card: item, plan_rate_card:)
        return started_at unless build.success?

        build.schedule.next_billing_at(after: Time.current) || started_at
      end

      def started_at
        @started_at ||= subscription.started_at || subscription.subscription_at
      end
    end
  end
end
