# frozen_string_literal: true

module Types
  module Charges
    class Properties < Types::BaseObject
      # NOTE: Standard and Package charge model
      field :amount, String, null: true, hash_key: :amount

      # NOTE: Graduated charge model
      field :graduated_ranges, [Types::Charges::GraduatedRange], null: true, hash_key: :graduated_ranges

      # NOTE: Graduated percentage modle
      field :graduated_percentage_ranges, [Types::Charges::GraduatedPercentageRange], null: true

      # NOTE: Package charge model
      field :free_units, GraphQL::Types::BigInt, null: true, hash_key: :free_units
      field :package_size, GraphQL::Types::BigInt, null: true, hash_key: :package_size

      # NOTE: Percentage charge model
      field :fixed_amount, String, null: true
      field :free_units_per_events, GraphQL::Types::BigInt, null: true
      field :free_units_per_total_aggregation, String, null: true
      field :per_transaction_max_amount, String, null: true
      field :per_transaction_min_amount, String, null: true
      field :rate, String, null: true

      # NOTE: Volume charge model
      field :volume_ranges, [Types::Charges::VolumeRange], null: true, hash_key: :volume_ranges
    end
  end
end
