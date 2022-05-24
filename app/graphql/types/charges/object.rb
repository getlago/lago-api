# frozen_string_literal: true

module Types
  module Charges
    class Object < Types::BaseObject
      graphql_name 'Charge'

      field :id, ID, null: false
      field :billable_metric, Types::BillableMetrics::Object, null: false
      field :charge_model, Types::Charges::ChargeModelEnum, null: false
      field :amount_currency, Types::CurrencyEnum, null: true

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      # NOTE: Standard and Package charge model
      field :amount, String, null: true

      # NOTE: Graduated charge model
      field :graduated_ranges, [Types::Charges::GraduatedRange], null: true

      # NOTE: Package charge model
      field :free_units, Integer, null: true
      field :package_size, Integer, null: true

      def amount
        return unless object.standard? || object.package?

        object.properties['amount']
      end

      def graduated_ranges
        return unless object.graduated?

        object.properties
      end

      def free_units
        return unless object.package?

        object.properties['free_units']
      end

      def package_size
        return unless object.package?

        object.properties['package_size']
      end
    end
  end
end
