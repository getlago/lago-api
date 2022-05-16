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

      # NOTE: Standard charge model
      field :amount_cents, Integer, null: true

      # NOTE: Graduated charge model
      field :graduated_ranges, [Types::Charges::GraduatedRange], null: true

      def amount_cents
        return unless object.standard?

        object.properties['amount_cents']
      end

      def graduated_ranges
        return unless object.graduated?

        object.properties
      end
    end
  end
end
