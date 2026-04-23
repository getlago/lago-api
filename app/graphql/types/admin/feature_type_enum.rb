# frozen_string_literal: true

module Types
  module Admin
    class FeatureTypeEnum < Types::BaseEnum
      graphql_name "AdminFeatureTypeEnum"

      value "premium_integration", "Premium integration toggle"
      value "feature_flag", "Feature flag toggle"
    end
  end
end
