# frozen_string_literal: true

module Types
  module Charges
    class PropertiesInput < Types::BaseInputObject
      # NOTE: Standard and Package charge model
      argument :amount, String, required: false

      # NOTE: Graduated charge model
      argument :graduated_ranges, [Types::Charges::GraduatedRangeInput], required: false

      # NOTE: Graduated percentage charge model
      argument :graduated_percentage_ranges, [Types::Charges::GraduatedPercentageRangeInput], required: false

      # NOTE: Package charge model
      argument :free_units, GraphQL::Types::BigInt, required: false
      argument :package_size, GraphQL::Types::BigInt, required: false

      # NOTE: Percentage charge model
      argument :fixed_amount, String, required: false
      argument :free_units_per_events, GraphQL::Types::BigInt, required: false
      argument :free_units_per_total_aggregation, String, required: false
      argument :per_transaction_max_amount, String, required: false
      argument :per_transaction_min_amount, String, required: false
      argument :rate, String, required: false

      # NOTE: Volume charge model
      argument :volume_ranges, [Types::Charges::VolumeRangeInput], required: false

      # NOTE: Timebased charge model
      argument :block_time_in_minutes, GraphQL::Types::BigInt, required: false
    end
  end
end
