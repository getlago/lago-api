# frozen_string_literal: true

module Billing
  module RateCards
    class BuildScheduleService < BaseService
      class MismatchedPlanRateCard < StandardError; end

      Result = BaseResult[:schedule]

      def initialize(contract_rate_card:, plan_rate_card: nil, ends_at: nil)
        @contract_rate_card = contract_rate_card
        @plan_rate_card = plan_rate_card
        @ends_at = ends_at
        super
      end

      def call
        rate_card = contract_rate_card.rate_card
        rates = rate_card.ordered_rates.to_a

        if rates.empty?
          result.not_found_failure!(resource: "rate")
        else
          terms = Terms.new(timing: rate_card.billing_timing, prorated: rate_card.proration?)

          result.schedule = Schedule.new(
            rates:,
            terms:,
            phases:,
            resume_at: contract_rate_card.billing_segments.maximum(:cycle_started_at),
            starts_at: contract_rate_card.effective_date.in_time_zone(timezone),
            ends_at: schedule_ends_at,
            anchor_date: contract_rate_card.billing_anchor_date,
            timezone:
          )
        end

        result
      rescue ArgumentError => error
        result.service_failure!(code: "invalid_billing_schedule", message: error.message)
      end

      private

      attr_reader :contract_rate_card, :plan_rate_card, :ends_at

      def timezone
        contract_rate_card.contract.customer.applicable_timezone
      end

      def schedule_ends_at
        # Contract card dates are inclusive; the walker expects an exclusive instant.
        card_end = contract_rate_card.ended_date&.next_day&.in_time_zone(timezone)

        [ends_at, card_end, contract_rate_card.contract.ended_at].compact.min
      end

      def phases
        rate_phases = ::ContractRateCards::ResolveRatePhasesService.call!(
          contract_rate_card:,
          plan_rate_card: resolved_plan_rate_card
        ).rate_phases

        configured = rate_phases.map do |rate_phase|
          Phase.new(
            code: rate_phase.code,
            billing_interval_cycle_count: rate_phase.billing_interval_cycle_count,
            rate_override: rate_phase.rate_override
          )
        end

        if configured.last&.unbounded?
          configured
        else
          configured + [Phase.default]
        end
      end

      def resolved_plan_rate_card
        if plan_rate_card.nil?
          contract_rate_card.contract.catalog_plan&.applied_rate_cards
            &.find { it.rate_card_id == contract_rate_card.rate_card_id }
        elsif plan_rate_card.rate_card_id != contract_rate_card.rate_card_id
          raise MismatchedPlanRateCard, "plan_rate_card #{plan_rate_card.id} prices rate card " \
            "#{plan_rate_card.rate_card_id}, not #{contract_rate_card.rate_card_id}"
        else
          plan_rate_card
        end
      end
    end
  end
end
