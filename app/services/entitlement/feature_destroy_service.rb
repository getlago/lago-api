# frozen_string_literal: true

module Entitlement
  class FeatureDestroyService < BaseService
    Result = BaseResult[:feature]

    def initialize(feature:)
      @feature = feature
      super
    end

    def call
      return result.not_found_failure!(resource: "feature") unless feature

      ActiveRecord::Base.transaction do
        feature.privileges.discard_all!
        feature.discard!
      end

      result.feature = feature
      result
    end

    private

    attr_reader :feature
  end
end
