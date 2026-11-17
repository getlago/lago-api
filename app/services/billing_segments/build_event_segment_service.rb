# frozen_string_literal: true

module BillingSegments
  # Adapts a priced schedule slice for event billing without writing a segment row.
  class BuildEventSegmentService < BaseService
    Result = BaseResult[:billing_segment]

    def initialize(contract_rate_card:, obligation:, segment:, pricing_units_by_code: nil)
      @contract_rate_card = contract_rate_card
      @obligation = obligation
      @segment = segment
      @pricing_units_by_code = pricing_units_by_code
      super
    end

    def call
      raise ArgumentError, "a billable segment needs a rate or an override to price it" unless segment.rate || rate_override

      result.billing_segment = BillingSegment.new(
        organization: contract_rate_card.organization,
        contract: contract_rate_card.contract,
        customer: contract_rate_card.contract.customer,
        contract_rate_card:,
        billable_metric_code: contract_rate_card.rate_card.product.billable_metric&.code,
        rate_card_rate: segment.rate,
        rate_override:,
        rate_properties: (rate_override || segment.rate).properties,
        currency: contract_rate_card.rate_card.currency,
        pricing_unit:,
        cycle_started_at: obligation.cycle.started_at,
        started_at: segment.started_at,
        ended_at: BillingSegment.inclusive_end(segment.ended_at),
        billing_at: terms.pricing_anchor_for(segment),
        proration_ratio: terms.prorated ? obligation.cycle.calendar.proration_ratio(segment.started_at, segment.ended_at) : 1.0
      )
      result
    end

    private

    attr_reader :contract_rate_card, :obligation, :segment, :pricing_units_by_code

    def rate_override
      obligation.cycle.phase.rate_override
    end

    def terms
      @terms ||= Billing::Terms.new(
        timing: contract_rate_card.rate_card.billing_timing,
        prorated: contract_rate_card.rate_card.proration?
      )
    end

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
