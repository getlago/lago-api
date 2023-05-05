# frozen_string_literal: true

module TaxRates
  class DestroyService < BaseService
    def initialize(tax_rate:)
      @tax_rate = tax_rate

      super
    end

    def call
      return result.not_found_failure!(resource: 'tax_rate') unless tax_rate

      tax_rate.destroy!

      result.tax_rate = tax_rate
      result
    end

    private

    attr_reader :tax_rate
  end
end
