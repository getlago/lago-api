# frozen_string_literal: true

module UsageAttributionTypes
  class DestroyService < BaseService
    Result = BaseResult[:usage_attribution_type]

    def initialize(usage_attribution_type:)
      @usage_attribution_type = usage_attribution_type
      super
    end

    def call
      return result.not_found_failure!(resource: "usage_attribution_type") unless usage_attribution_type

      ActiveRecord::Base.transaction do
        usage_attribution_type.usage_attribution_values.discard_all!
        usage_attribution_type.discard!
      end

      result.usage_attribution_type = usage_attribution_type
      result
    end

    private

    attr_reader :usage_attribution_type
  end
end
