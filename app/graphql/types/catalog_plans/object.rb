# frozen_string_literal: true

module Types
  module CatalogPlans
    class Object < Types::BaseObject
      graphql_name "CatalogPlan"
      description "A product-catalog plan"

      field :id, ID, null: false
      field :organization, Types::Organizations::OrganizationType

      field :code, String, null: false
      field :description, String, null: true
      field :invoice_display_name, String, null: true
      field :name, String, null: false

      # The catalog surface exposes the currency under the legacy amountCurrency
      # field name; the model stores it natively as `currency`.
      field :amount_currency, Types::CurrencyEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
