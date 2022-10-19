# frozen_string_literal: true

module Types
  module Charges
    class Properties < Types::BaseObject
      graphql_name 'Properties'

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
        object['amount']
      end

      def graduated_ranges
        object['graduated_ranges']
      end

      def free_units
        object['free_units']
      end

      def package_size
        object['package_size']
      end

      def rate
        object['rate']
      end

      def fixed_amount
        object['fixed_amount']
      end

      def free_units_per_events
        object['free_units_per_events']
      end

      def free_units_per_total_aggregation
        object['free_units_per_total_aggregation']
      end

      def volume_ranges
        object['volume_ranges']
      end
    end
  end
end
