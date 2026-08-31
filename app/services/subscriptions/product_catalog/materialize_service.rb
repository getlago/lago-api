# frozen_string_literal: true

module Subscriptions
  module ProductCatalog
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
        item.next_billing_at = initial_next_billing_at(item)
        item.save!
        item
      end

      def initial_next_billing_at(item)
        rate = item.rate_card&.rate_active_at(started_at)
        return started_at unless rate

        period = calendar_for(item, rate).period_at(first_billable_at)
        opens_at = [period.begin, billing_starts_at].max

        item.rate_card.advance? ? opens_at : period.end
      end

      def calendar_for(item, rate)
        Billing::Calendar.new(
          anchor_date: item.billing_anchor_date,
          interval: Billing::Interval.new(count: rate.billing_interval_count, unit: rate.billing_interval_unit),
          timezone:
        )
      end

      # A backdated subscription bills the period it lands in today, not the ones it
      # missed. The gap is deliberate: the past is either already invoiced elsewhere or
      # given away, and back-billing it on signup would surprise the customer.
      def first_billable_at
        [started_at, Time.current].max
      end

      # Cycles start at the beginning of a day in the customer's timezone, so a card
      # signed at 14:30 is billed for the whole of that day.
      def billing_starts_at
        started_at.in_time_zone(timezone).beginning_of_day
      end

      def timezone
        @timezone ||= subscription.customer.applicable_timezone
      end

      def started_at
        @started_at ||= subscription.started_at || subscription.subscription_at
      end
    end
  end
end
