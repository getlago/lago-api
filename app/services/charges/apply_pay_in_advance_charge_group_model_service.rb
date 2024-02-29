# frozen_string_literal: true

module Charges
  class ApplyPayInAdvanceChargeGroupModelService < BaseService
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

      amount = charge_model.apply(charge:, aggregation_result:, properties:).amount

      # NOTE: amount_result should be a BigDecimal, we need to round it
      # to the currency decimals and transform it into currency cents
      rounded_amount = amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit
      
      result.units = compute_units
      result.count = 1
      result.amount = amount_cents
      result
    end

    private

    attr_reader :charge, :aggregation_result, :properties

    def charge_model
      @charge_model ||= case charge.charge_model.to_sym
                        when :package_group
                          Charges::ChargeModels::PackageGroupService
                        else
                          raise(NotImplementedError)
      end
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
