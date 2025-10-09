# frozen_string_literal: true

module Types
  module Subscriptions
    class FixedChargeOverridesInput < Types::BaseInputObject
      argument :add_on_id, ID, required: true
      argument :id, ID, required: false

      argument :invoice_display_name, String, required: false
      argument :properties, Types::FixedCharges::PropertiesInput, required: false
      argument :tax_codes, [String], required: false
      argument :units, String, required: true
    end
  end
end
