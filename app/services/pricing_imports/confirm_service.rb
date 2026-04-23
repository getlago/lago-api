# frozen_string_literal: true

module PricingImports
  class ConfirmService < BaseService
    Result = BaseResult[:pricing_import]

    def initialize(pricing_import:)
      @pricing_import = pricing_import
      super
    end

    def call
      unless pricing_import.draft?
        return result.validation_failure!(errors: {state: ["cannot_confirm_from_#{pricing_import.state}"]})
      end

      pricing_import.update!(state: "confirmed")
      PricingImports::ExecuteJob.perform_later(pricing_import.id)

      result.pricing_import = pricing_import
      result
    end

    private

    attr_reader :pricing_import
  end
end
