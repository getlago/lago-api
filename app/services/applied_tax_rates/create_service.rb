# frozen_string_literal: true

module AppliedTaxRates
  class CreateService < BaseService
    def initialize(customer:, tax_rate:)
      @customer = customer
      @tax_rate = tax_rate
      super
    end

    def call
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'tax_rate') unless tax_rate

      applied_tax_rate = customer.applied_tax_rates.create!(tax_rate:)

      result.applied_tax_rate = applied_tax_rate
      result
    end

    private

    attr_reader :customer, :tax_rate
  end
end
