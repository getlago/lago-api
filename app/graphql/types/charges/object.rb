# frozen_string_literal: true

module Types
  module Charges
    class Object < Types::BaseObject
      graphql_name 'Charge'

      field :id, ID, null: false
      field :billable_metric, Types::BillableMetrics::Object, null: false
      field :charge_model, Types::Charges::ChargeModelEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

      # NOTE: Standard and Package charge model
      field :amount, String, null: true

      # NOTE: Graduated charge model
      field :graduated_ranges, [Types::Charges::GraduatedRange], null: true

      # NOTE: Package charge model
      field :free_units, Integer, null: true
      field :package_size, Integer, null: true

      # NOTE: Percentage charge model
      field :rate, String, null: true
      field :fixed_amount, String, null: true
      field :free_units_per_events, Integer, null: true
      field :free_units_per_total_aggregation, String, null: true

      # NOTE: Volume charge model
      field :volume_ranges, [Types::Charges::VolumeRange], null: true

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

      def rate
        return unless object.percentage?

        object.properties['rate']
      end

      def fixed_amount
        return unless object.percentage?

        object.properties['fixed_amount']
      end

      def free_units_per_events
        return unless object.percentage?

        object.properties['free_units_per_events']
      end

      def free_units_per_total_aggregation
        return unless object.percentage?

        object.properties['free_units_per_total_aggregation']
      end

      def volume_ranges
        return unless object.volume?

        object.properties['ranges']
      end
    end
  end
end
