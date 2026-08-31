# frozen_string_literal: true

module Billing
  module Schedules
    # Reads one rate card and hands back the schedule it bills on. The only place in the
    # billing date layer that touches ActiveRecord — everything below it works on plain
    # values and can be exercised without a database.
    #
    # NOTE: the cadence is taken from the rate in force when the card started. A later rate
    # carrying a different billing_interval would not move it. The old engine resolved the
    # interval per cycle instead; whether a rate may change the cadence at all is a product
    # question, and the QA plan only ever changes it through a phase (PH3).
    class BuildService < BaseService
      Result = BaseResult[:schedule]

      def initialize(subscription_rate_card:, plan_rate_cards: [])
        @subscription_rate_card = subscription_rate_card
        @plan_rate_cards = plan_rate_cards
        super
      end

      def call
        return result.not_found_failure!(resource: "rate") unless base_rate

        result.schedule = Billing::Schedule.new(
          anchor_date: subscription_rate_card.billing_anchor_date,
          timezone:,
          starts_at:,
          ends_at: subscription_rate_card.ended_at,
          timing: subscription_rate_card.rate_card.billing_timing,
          phases:
        )
        result
      end

      private

      attr_reader :subscription_rate_card, :plan_rate_cards

      def timezone
        @timezone ||= subscription_rate_card.subscription.customer.applicable_timezone
      end

      # Cycles open at the start of a day in the customer's timezone, so a card attached at
      # 12:34 bills that whole day. Anchored on the card rather than on this version of it:
      # a units change opens a new row, and using that row's own start would clip every
      # period to the moment the quantity last moved.
      def starts_at
        @starts_at ||= subscription_rate_card.card_started_at.in_time_zone(timezone).beginning_of_day
      end

      def base_rate
        @base_rate ||= subscription_rate_card.rate_card.rate_active_at(starts_at)
      end

      # One phase per configured rate phase, and an open one to close the list. A card with
      # no phases bills on its own cadence forever, and so does one whose phases are all
      # bounded — which is what rate_phase_for_cycle returning nil means today.
      def phases
        configured = rate_phases.map do |phase|
          Billing::Schedule::Phase.new(
            cycle_count: phase.billing_interval_cycle_count,
            interval: Billing::Interval.from(base_rate, override: phase.rate_override),
            code: phase.code,
            override: phase.rate_override
          )
        end

        return configured if configured.last && configured.last.cycle_count.nil?

        configured + [tail_phase]
      end

      def tail_phase
        Billing::Schedule::Phase.new(cycle_count: nil, interval: Billing::Interval.from(base_rate), code: nil, override: nil)
      end

      def rate_phases
        ::SubscriptionRateCards::ResolveRatePhasesService.call!(
          subscription_rate_card:,
          plan_rate_cards:
        ).rate_phases.phases
      end
    end
  end
end
