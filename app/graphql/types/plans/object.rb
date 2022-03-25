# frozen_string_literal: true

module Types
  module Plans
    class Object < Types::BaseObject
      graphql_name 'Plan'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :name, String, null: false
      field :code, String, null: false
      field :frequency, Types::Plans::FrequencyEnum, null: false
      field :billing_period, Types::Plans::BillingPeriodEnum, null: false
      field :pro_rata, Boolean, null: false
      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false
      field :vat_rate, Float
      field :trial_period, Float
      field :description, String

      field :charges, [Types::Charges::Object]

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
