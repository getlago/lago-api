# frozen_string_literal: true

module Types
  module RateProperties
    # Charge properties with catalog tiers, which only carry their upper bound.
    class PropertiesInput < Types::Charges::PropertiesInput
      graphql_name "RatePropertiesInput"

      argument :graduated_percentage_ranges, [Types::RateProperties::PercentageTierInput], required: false
      argument :graduated_ranges, [Types::RateProperties::TierInput], required: false
      argument :volume_ranges, [Types::RateProperties::TierInput], required: false
    end
  end
end
