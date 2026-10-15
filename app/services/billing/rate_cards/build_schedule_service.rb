# frozen_string_literal: true

module Billing
  module RateCards
    class BuildScheduleService < BaseService
      Result = BaseResult[:schedule]

      def initialize(contract_rate_card:, ends_at: nil, resume_from_billing_segments: true)
        @contract_rate_card = contract_rate_card
        @ends_at = ends_at
        @resume_from_billing_segments = resume_from_billing_segments
        super
      end

      def call
        rate_card = contract_rate_card.rate_card
        rates = if rate_card.rates.loaded?
          rate_card.rates.sort_by(&:effective_from)
        else
          rate_card.ordered_rates.to_a
        end

        if rates.empty?
          result.not_found_failure!(resource: "rate")
        else
          terms = Terms.new(timing: rate_card.billing_timing, prorated: rate_card.proration?)

          result.schedule = Schedule.new(
            rates:,
            terms:,
            phases:,
            resume_at: resume_from_billing_segments ? contract_rate_card.billing_segments.maximum(:cycle_started_at) : nil,
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

      attr_reader :contract_rate_card, :ends_at, :resume_from_billing_segments

      def timezone
        contract_rate_card.contract.customer.applicable_timezone
      end

      def schedule_ends_at
        [ends_at, contract_rate_card.contract.ended_at].compact.min
      end

      def phases
        configured = contract_rate_card.rate_phases.map do |rate_phase|
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
    end
  end
end
