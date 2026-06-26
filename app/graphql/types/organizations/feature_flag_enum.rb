# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Organizations
    class FeatureFlagEnum < Types::BaseEnum
      description "Organization Feature Flag Values"

      FeatureFlag::DEFINITION.each_key do |flag|
        value flag
      end
    end
  end
end
