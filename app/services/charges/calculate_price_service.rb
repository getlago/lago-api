# frozen_string_literal: true

module Charges
  class CalculatePriceService < BaseService
    Result = BaseResult[:charge_amount_cents, :subscription_amount_cents, :total_amount_cents]
    AggregationResult = Struct.new(:aggregation, :total_aggregated_units, :current_usage_units, :full_units_number)

    def initialize(subscription:, units:, charge:, charge_filter: nil)
      @subscription = subscription
      @units = units
      @charge = charge
      @charge_filter = charge_filter
      @billable_metric = charge&.billable_metric

      super
    end

    def call
      result.charge_amount_cents = calculate_charge_amount
      result.subscription_amount_cents = plan.amount_cents
      result.total_amount_cents = result.charge_amount_cents + result.subscription_amount_cents
      result
    end

    private

    attr_reader :subscription, :units, :billable_metric, :charge, :charge_filter

    delegate :plan, to: :subscription
    delegate :customer, to: :subscription

    def calculate_charge_amount
      return 0 unless charge

      properties = charge_filter&.properties ||
        charge.properties.presence ||
        Charges::BuildDefaultPropertiesService.call(charge.charge_model)

      filtered_properties = Charges::FilterChargeModelPropertiesService.call(charge:, properties:).properties

      charge_model = ChargeModelFactory.new_instance(
        charge:,
        aggregation_result:,
        properties: filtered_properties
      )

      charge_model.apply.amount
    end

    def aggregation_result
      AggregationResult.new(units, units, units, units)
    end
  end
end
