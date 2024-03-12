# frozen_string_literal: true

module Types
  module ChargeGroups
    class Object < Types::BaseObject
      graphql_name 'ChargeGroup'

      field :id, ID, null: false
      field :invoice_display_name, String, null: true

      field :charges, [Types::Charges::Object]
      field :usage_charge_groups, [Types::UsageChargeGroups::Object]

      field :invoiceable, Boolean, null: false
      field :min_amount_cents, GraphQL::Types::BigInt, null: false
      field :pay_in_advance, Boolean, null: false
      field :properties, Types::ChargeGroups::Properties, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      # TODO: check if this is needed
      delegate :charges, to: :object
      delegate :usage_charge_groups, to: :object
    end
  end
end
