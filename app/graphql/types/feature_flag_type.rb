# frozen_string_literal: true

module Types
  class FeatureFlagType < Types::BaseObject
    description 'Feature Flag Type'

    FeatureFlag::FEATURES.each do |feature, attr|
      field feature, Boolean, attr[:description], null: false
    end
  end
end
