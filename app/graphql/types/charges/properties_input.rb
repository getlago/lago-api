# frozen_string_literal: true

module Types
  module Charges
    class PropertiesInput < Types::BaseInputObject
      # NOTE: Standard and Package charge model
      argument :amount, String, required: false

      # NOTE: Graduated charge model
      argument :graduated_ranges, [Types::Charges::GraduatedRangeInput], required: false

      # NOTE: Package charge model
      argument :free_units, GraphQL::Types::BigInt, required: false
      argument :package_size, GraphQL::Types::BigInt, required: false

      # NOTE: Percentage charge model
      argument :rate, String, required: false
      argument :fixed_amount, String, required: false
      argument :free_units_per_events, GraphQL::Types::BigInt, required: false
      argument :free_units_per_total_aggregation, String, required: false

      # NOTE: Volume charge model
      argument :volume_ranges, [Types::Charges::VolumeRangeInput], required: false
    end
  end
end
