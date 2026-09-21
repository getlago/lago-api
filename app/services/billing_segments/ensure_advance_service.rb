# frozen_string_literal: true

module BillingSegments
  class EnsureAdvanceService < BaseService
    Result = BaseResult[:billing_segment]

    def initialize(contract_rate_card:, timestamp: Time.current)
      @contract_rate_card = contract_rate_card
      @timestamp = timestamp
      super
    end

    def call
      return result unless advance_metered?
      return result unless contract_rate_card.rate_card.rates.exists?

      Customers::LockService.call!(customer: contract.customer, scope: :billing_schedule) do
        contract_rate_card.with_lock do
          result.billing_segment = stored_segment || create_segment
        end
      end

      result
    end

    private

    attr_reader :contract_rate_card, :timestamp

    delegate :contract, :rate_card, to: :contract_rate_card

    def advance_metered?
      rate_card.advance? && rate_card.product.metered?
    end

    def reference_at
      @reference_at ||= [timestamp, contract.started_at].compact.max
    end

    def stored_segment
      contract_rate_card.billing_segments
        .where("started_at <= ? AND ended_at >= ?", reference_at, reference_at)
        .first || contract_rate_card.billing_segments.where(started_at: reference_at..).order(:started_at).first
    end

    def create_segment
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
      billing_at = schedule.billing_at_covering(reference_at)
      return unless billing_at

      billable_segment = schedule
        .segments_overlapping(billing_at...(billing_at + BillingSegment::MICROSECOND))
        .find { |segment| segment.billing_at == billing_at }
      return unless billable_segment

      BillingSegments::CreateService.call!(
        contract_rate_card:,
        billable_segments: [billable_segment],
        pricing_unit:
      ).billing_segments.sole
    end

    def pricing_unit
      code = rate_card.applied_pricing_unit_code.presence
      return unless code

      contract.organization.pricing_units.find_by(code:) || result.not_found_failure!(resource: "pricing_unit").raise_if_error!
    end
  end
end
