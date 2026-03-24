# frozen_string_literal: true

module Types
  module Organizations
    class FeatureFlagEnum < Types::BaseEnum
      description "Organization Feature Flag Values"

      FeatureFlag::DEFINITION.filter { |_, v| !v[:backend_only] }.each_key do |flag|
        value flag
      end
    end
  end
end
