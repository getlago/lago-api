# frozen_string_literal: true

module Customers
  class UpdateCurrencyService < BaseService
    def initialize(customer:, currency:, customer_update: false)
      @customer = customer
      @currency = currency
      @customer_update = customer_update

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result if customer.currency == currency

      if customer_update
        # NOTE: direct update of the customer currency
        unless customer.editable?
          return result.single_validation_failure!(
            field: :currency,
            error_code: "currencies_does_not_match"
          )
        end
      elsif customer.currency.present? || !customer.editable?
        # NOTE: Assign currency from another resource
        return result.single_validation_failure!(
          field: :currency,
          error_code: "currencies_does_not_match"
        )
      end

      customer.update!(currency:)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :currency, :customer_update
  end
end
