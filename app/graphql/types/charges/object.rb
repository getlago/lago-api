# frozen_string_literal: true

module Types
  module Charges
    class Object < Types::BaseObject
      graphql_name 'Charge'

      field :billable_metric, Types::BillableMetrics::Object, null: false
      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :frequency, Types::Charges::FrequencyEnum, null: false
      field :pro_rata, Boolean, null: false
      field :vat_rate, Float

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
