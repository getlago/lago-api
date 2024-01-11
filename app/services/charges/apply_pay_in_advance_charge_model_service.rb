# frozen_string_literal: true

module Charges
  class ApplyPayInAdvanceChargeModelService < BaseService
    def initialize(charge:, aggregation_result:, properties:)
      @charge = charge
      @aggregation_result = aggregation_result
      @properties = properties

      super
    end

    def call
      unless charge.pay_in_advance?
        return result.service_failure!(code: 'apply_charge_model_error', message: 'Charge is not pay_in_advance')
      end

      amount = amount_including_event - amount_excluding_event

      # NOTE: amount_result should be a BigDecimal, we need to round it
      # to the currency decimals and transform it into currency cents
      rounded_amount = amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit

      result.units = compute_units
      result.count = 1
      result.amount = amount_cents
      result.unit_amount = rounded_amount.zero? ? BigDecimal(0) : rounded_amount / compute_units
      result
    end

    private

    attr_reader :charge, :aggregation_result, :properties

    def charge_model
      @charge_model ||= case charge.charge_model.to_sym
                        when :standard
                          Charges::ChargeModels::StandardService
                        when :graduated
                          Charges::ChargeModels::GraduatedService
                        when :graduated_percentage
                          Charges::ChargeModels::GraduatedPercentageService
                        when :package
                          Charges::ChargeModels::PackageService
                        when :percentage
                          Charges::ChargeModels::PercentageService
                        else
                          raise(NotImplementedError)
      end
    end

    def amount_including_event
      charge_model.apply(charge:, aggregation_result:, properties:).amount
    end

    def amount_excluding_event
      previous_result = BaseService::Result.new
      previous_result.aggregation = aggregation_result.aggregation - aggregation_result.pay_in_advance_aggregation
      previous_result.count = aggregation_result.count - 1
      previous_result.options = aggregation_result.options
      previous_result.aggregator = aggregation_result.aggregator

      charge_model.apply(
        charge:,
        aggregation_result: previous_result,
        properties: (properties || {}).merge(ignore_last_event: true),
      ).amount
    end

    def currency
      @currency ||= charge.plan.amount.currency
    end

    def compute_units
      if display_applied_units_for_zero_invoice?
        units_applied = BigDecimal(aggregation_result.units_applied)
        units_applied.negative? ? 0 : units_applied
      elsif charge.prorated?
        aggregation_result.full_units_number
      else
        aggregation_result.pay_in_advance_aggregation
      end
    end

    def display_applied_units_for_zero_invoice?
      aggregation_result.current_aggregation &&
        aggregation_result.max_aggregation &&
        aggregation_result.units_applied &&
        aggregation_result.current_aggregation <= aggregation_result.max_aggregation
    end
  end
end
