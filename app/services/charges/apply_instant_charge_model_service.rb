# frozen_string_literal: true

module Charges
  class ApplyInstantChargeModelService < BaseService
    def initialize(charge:, aggregation_result:, properties:)
      @charge = charge
      @aggregation_result = aggregation_result
      @properties = properties

      super
    end

    def call
      unless charge.instant?
        return result.service_failure!(code: 'apply_charge_model_error', message: 'Charge is not instant')
      end

      amount = amount_including_event - amount_excluding_event

      # NOTE: amount_result should be a BigDecimal, we need to round it
      # to the currency decimals and transform it into currency cents
      rounded_amount = amount.round(currency.exponent)
      amount_cents = rounded_amount * currency.subunit_to_unit

      result.units = aggregation_result.instant_aggregation
      result.count = 1
      result.amount = amount_cents
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
      previous_result.aggregation = aggregation_result.aggregation - aggregation_result.instant_aggregation
      previous_result.count = aggregation_result.count - 1
      previous_result.options = aggregation_result.options

      charge_model.apply(charge:, aggregation_result: previous_result, properties:).amount
    end

    def currency
      @currency ||= charge.plan.amount.currency
    end
  end
end
