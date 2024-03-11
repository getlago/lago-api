# frozen_string_literal: true

module Types
  module ChargeGroups
    class Input < Types::BaseInputObject
      graphql_name 'ChargeGroupInput'

      argument :id, ID, required: false
      argument :invoice_display_name, String, required: false

      argument :invoiceable, Boolean, required: false
      argument :min_amount_cents, GraphQL::Types::BigInt, required: false
      argument :pay_in_advance, Boolean, required: false

      argument :properties, Types::ChargeGroups::PropertiesInput, required: false
    end
  end
end
