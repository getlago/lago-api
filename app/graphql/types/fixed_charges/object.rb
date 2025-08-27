# frozen_string_literal: true

module Types
  module FixedCharges
    class Object < Types::BaseObject
      graphql_name "FixedCharge"

      field :id, ID, null: false
      field :invoice_display_name, String, null: true

      field :add_on, Types::AddOns::Object, null: false
      field :charge_model, Types::FixedCharges::ChargeModelEnum, null: false
      field :pay_in_advance, Boolean, null: false
      field :properties, Types::FixedCharges::Properties, null: true
      field :prorated, Boolean, null: false
      field :units, String, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :deleted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      field :taxes, [Types::Taxes::Object]

      def properties
        return object.properties unless object.properties == "{}"

        JSON.parse(object.properties)
      end

      def add_on
        AddOn.with_discarded.find_by(id: object.add_on_id)
      end

      def units
        # If we have subscription context, check for overridden units
        if subscription_context = instance_variable_get(:@subscription_context)
          override = subscription_context.subscription_fixed_charge_units_overrides.find_by(fixed_charge: object)
          return override.units.to_s if override
        end
        
        # Return the default units from the fixed charge
        object.units.to_s
      end
    end
  end
end
