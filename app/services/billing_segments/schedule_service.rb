# frozen_string_literal: true

module BillingSegments
  # Produces customer due billing segments. It resolves what a run needs once — the card's
  # schedule, its pricing unit — and hands them down, so no collaborator looks anything up.
  class ScheduleService < BaseService
    OVERLAP_CONSTRAINT = "billing_segments_no_overlapping_periods"

    Result = BaseResult[:billing_segments]

    def initialize(customer:, timestamp: Time.current)
      @customer = customer
      @timestamp = timestamp
      super
    end

    def call
      result.billing_segments = []
      scheduled = []

      ActiveRecord::Base.transaction do
        Customers::LockService.call!(customer:, scope: :billing_schedule) do
          due_cards.find_each { |card| scheduled.concat(schedule_card(card)) }
        end
      end

      result.billing_segments = scheduled
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue ActiveRecord::StatementInvalid => error
      if overlapping_periods?(error)
        result.single_validation_failure!(error_code: "overlapping_periods", field: :billing_segment)
      else
        raise
      end
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :customer, :timestamp

    def due_cards
      ContractRateCard.due_for_billing(timestamp)
        .where(organization_id: customer.organization_id, contracts: {customer_id: customer.id})
        .includes(
          :rate_card,
          {rate_phases: :rate_override},
          contract: :customer
        )
    end

    def schedule_card(card)
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule
      pricing_unit = pricing_unit_of(card)

      missing = MissingBillableSegmentsService.call!(contract_rate_card: card, schedule:, timestamp:)
      written = CreateService.call!(
        contract_rate_card: card,
        billable_segments: missing.billable_segments,
        pricing_unit:
      ).billing_segments

      ContractRateCards::AdvanceBillingClockService.call!(contract_rate_card: card, schedule:, timestamp:)
      written
    end

    def pricing_unit_of(card)
      code = card.rate_card.applied_pricing_unit_code

      if code.present?
        pricing_units_by_code.fetch(code) { result.not_found_failure!(resource: "pricing_unit").raise_if_error! }
      end
    end

    def pricing_units_by_code
      @pricing_units_by_code ||= customer.organization.pricing_units.index_by(&:code)
    end

    def overlapping_periods?(error)
      (error.cause&.message || error.message).include?(OVERLAP_CONSTRAINT)
    end
  end
end
