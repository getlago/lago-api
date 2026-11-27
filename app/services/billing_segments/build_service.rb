# frozen_string_literal: true

module BillingSegments
  # Adapts a raw schedule segment to pricing input for events, current usage and invoicing.
  class BuildService < BaseService
    Result = BaseResult[:billing_segment]

    def initialize(contract_rate_card:, rate_card_rate:, rate_override:, started_at:, ended_at:, cycle_started_at:, billing_at:,
      proration_ratio:, pricing_units_by_code: nil)
      @contract_rate_card = contract_rate_card
      @rate_card_rate = rate_card_rate
      @rate_override = rate_override
      @window = {cycle_started_at:, started_at:, ended_at: BillingSegment.inclusive_end(ended_at), billing_at:, proration_ratio:}
      @pricing_units_by_code = pricing_units_by_code
      super
    end

    def call
      effective_rate = rate_override || rate_card_rate
      raise ArgumentError, "a billable segment needs a rate or an override to price it" unless effective_rate

      result.billing_segment = BillingSegment.new(
        organization: contract_rate_card.organization,
        contract: contract_rate_card.contract,
        customer: contract_rate_card.contract.customer,
        contract_rate_card:,
        billable_metric_code: contract_rate_card.rate_card.product.billable_metric&.code,
        rate_card_rate:,
        rate_override:,
        rate_properties: effective_rate.properties,
        currency: contract_rate_card.rate_card.currency,
        pricing_unit:,
        **window
      )
      result
    end

    private

    attr_reader :contract_rate_card, :rate_card_rate, :rate_override, :pricing_units_by_code, :window

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
