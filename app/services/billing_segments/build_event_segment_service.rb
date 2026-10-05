# frozen_string_literal: true

module BillingSegments
  # Adapts a priced schedule slice for event billing without writing a segment row.
  class BuildEventSegmentService < BaseService
    Result = BaseResult[:billing_segment]

    def initialize(contract_rate_card:, billable_segment:, pricing_units_by_code: nil)
      @contract_rate_card = contract_rate_card
      @billable_segment = billable_segment
      @pricing_units_by_code = pricing_units_by_code
      super
    end

    def call
      result.billing_segment = BillingSegment.new(
        organization: contract_rate_card.organization,
        contract: contract_rate_card.contract,
        customer: contract_rate_card.contract.customer,
        contract_rate_card:,
        rate_card_rate: billable_segment.rate,
        rate_override: billable_segment.rate_override,
        rate_properties: billable_segment.properties,
        currency: contract_rate_card.rate_card.currency,
        pricing_unit:,
        cycle_started_at: billable_segment.cycle_started_at,
        started_at: billable_segment.started_at,
        ended_at: BillingSegment.inclusive_end(billable_segment.ended_at),
        billing_at: billable_segment.billing_at,
        proration_ratio: billable_segment.proration_ratio,
        status: :pending
      )
      result
    end

    private

    attr_reader :contract_rate_card, :billable_segment, :pricing_units_by_code

    def pricing_unit
      code = contract_rate_card.rate_card.applied_pricing_unit_code
      return if code.blank?

      unit = if pricing_units_by_code
        pricing_units_by_code[code]
      else
        contract_rate_card.organization.pricing_units.find_by(code:)
      end

      unit || result.not_found_failure!(resource: "pricing_unit").raise_if_error!
    end
  end
end
