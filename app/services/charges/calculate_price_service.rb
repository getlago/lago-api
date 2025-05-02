# frozen_string_literal: true

module Charges
  class CalculatePriceService < BaseService
    Result = BaseResult[:charge_amount_cents, :subscription_amount_cents, :total_amount_cents]

    def initialize(billable_metric:, subscription:, date:, units:)
      @billable_metric = billable_metric
      @subscription = subscription
      @date = date
      @units = units

      super
    end

    def call
      result.charge_amount_cents = calculate_charge_amount
      result.subscription_amount_cents = plan.amount_cents
      result.total_amount_cents = result.charge_amount_cents + result.subscription_amount_cents
      result
    end

    private

    attr_reader :billable_metric, :subscription, :date, :units

    delegate :plan, to: :subscription
    delegate :customer, to: :subscription

    def calculate_charge_amount
      charge = subscription.plan.charges.find_by(billable_metric:)
      return 0 unless charge

      properties = charge.properties.presence || Charges::BuildDefaultPropertiesService.call(charge.charge_model)

      filtered_properties = Charges::FilterChargeModelPropertiesService.call(charge:, properties:).properties

      charge_model = ChargeModelFactory.new_instance(
        charge:,
        aggregation_result: build_aggregation_result,
        properties: filtered_properties
      )

      charge_model.apply.amount
    end

    def build_aggregation_result
      OpenStruct.new(
        aggregation: units,
        total_aggregated_units: units,
        current_usage_units: units
      )
    end
  end
end
