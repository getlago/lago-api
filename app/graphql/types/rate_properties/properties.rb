# frozen_string_literal: true

module Types
  module RateProperties
    # Charge properties with catalog tiers, resolved from ::RateProperties.present.
    class Properties < Types::Charges::Properties
      graphql_name "RateProperties"

      field :graduated_percentage_ranges, [Types::RateProperties::PercentageTier], null: true
      field :graduated_ranges, [Types::RateProperties::Tier], null: true
      field :volume_ranges, [Types::RateProperties::Tier], null: true
    end
  end
end
