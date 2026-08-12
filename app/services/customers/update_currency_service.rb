# frozen_string_literal: true

module Customers
  class UpdateCurrencyService < BaseService
    Result = BaseResult

    def initialize(customer:, currency:, customer_update: false)
      @customer = customer
      @currency = currency
      @customer_update = customer_update

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result if customer.currency == currency

      # Multi-currency: customer.currency becomes a default preference, not a constraint.
      customer.update!(currency:) if customer_update || customer.currency.blank?
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :currency, :customer_update
  end
end
