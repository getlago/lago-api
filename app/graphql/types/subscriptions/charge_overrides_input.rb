# frozen_string_literal: true

module Types
  module Subscriptions
    class ChargeOverridesInput < Types::BaseInputObject
      argument :group_properties, [Types::Charges::GroupPropertiesInput]
      argument :min_amount_cents, GraphQL::Types::BigInt
      argument :properties, Types::Charges::PropertiesInput
      argument :tax_codes, [String]
    end
  end
end
