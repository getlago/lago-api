# frozen_string_literal: true

module AppliedTaxRates
  class DestroyService < BaseService
    def initialize(applied_tax_rate:)
      @applied_tax_rate = applied_tax_rate
      super
    end

    def call
      return result.not_found_failure!(resource: 'applied_tax_rate') unless applied_tax_rate

      applied_tax_rate.destroy!

      result.applied_tax_rate = applied_tax_rate
      result
    end

    private

    attr_reader :applied_tax_rate
  end
end
