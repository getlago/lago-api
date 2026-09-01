# frozen_string_literal: true

module Billing
  module RateCards
    class BuildScheduleService < BaseService
      Result = BaseResult[:schedule]

      def initialize(subscription_rate_card:, plan_rate_card: nil, ends_at: nil, realign_billing_anchor: true)
        @subscription_rate_card = subscription_rate_card
        @plan_rate_card = plan_rate_card
        @ends_at = ends_at
        @realign_billing_anchor = realign_billing_anchor
        super
      end

      def call
        if rates.empty?
          result.not_found_failure!(resource: "rate")
        else
          result.schedule = build_schedule
        end

        result
      end

      private

      attr_reader :subscription_rate_card, :plan_rate_card, :ends_at, :realign_billing_anchor

      def build_schedule
        Schedule.new(
          anchor_date: subscription_rate_card.billing_anchor_date,
          rates:,
          prorated: subscription_rate_card.rate_card.proration?,
          realign_billing_anchor:,
          timezone:,
          starts_at:,
          ends_at: ends_at || subscription_rate_card.ended_at,
          timing: subscription_rate_card.rate_card.billing_timing,
          phases:
        )
      end

      def timezone
        @timezone ||= subscription_rate_card.customer.applicable_timezone
      end

      # Read off the card, not this version of it: a units change opens a new row, and using
      # that row's own start would clip every cycle to the moment the quantity last moved.
      def starts_at
        subscription_rate_card.card_started_at
      end

      def phases
        configured = rate_phases.map do |phase|
          Schedule::Phase.new(
            cycle_count: phase.billing_interval_cycle_count,
            code: phase.code,
            override: phase.rate_override
          )
        end

        if configured.last && configured.last.cycle_count.nil?
          configured
        else
          configured + [Schedule::Phase.default]
        end
      end

      def rates
        @rates ||= subscription_rate_card.rate_card.rates.order(:effective_from).to_a
      end

      def rate_phases
        ::SubscriptionRateCards::ResolveRatePhasesService.call!(
          subscription_rate_card:,
          plan_rate_card:
        ).rate_phases
      end
    end
  end
end
