# frozen_string_literal: true

module Types
  module Invoices
    class ForecastedFee < Types::BaseObject
      graphql_name 'ForecastedFee'

      field :billable_metric_name, String, null: false
      field :billable_metric_code, String, null: false
      field :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, null: false
      field :charge_model, Types::Charges::ChargeModelEnum, null: false

      field :units, Integer, null: false
      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :vat_amount_cents, Integer, null: false
      field :vat_amount_currency, Types::CurrencyEnum, null: false

      def billable_metric_name
        object.billable_metric.name
      end

      def billable_metric_code
        object.billable_metric.code
      end

      def aggregation_type
        object.billable_metric.aggregation_type
      end

      def charge_model
        object.charge.charge_model
      end
    end
  end
end
