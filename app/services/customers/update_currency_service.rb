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

      if multi_currency_enabled?
        return result unless allowed_with_multi_currency?
      else
        return result unless allowed_without_multi_currency?
      end

      customer.update!(currency:)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :currency, :customer_update

    def multi_currency_enabled?
      customer.organization.feature_flag_enabled?(:multi_currency)
    end

    def allowed_without_multi_currency?
      if customer_update
        unless customer.editable?
          result.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
          return false
        end
      elsif customer.currency.present? || !customer.editable?
        result.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
        return false
      end
      true
    end

    def allowed_with_multi_currency?
      if customer_update && committed_invoices_in_different_currency?
        result.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
        return false
      elsif !customer_update && customer.currency.present?
        return false
      end
      true
    end

    def committed_invoices_in_different_currency?
      customer.invoices
        .where(status: %i[finalized open closed])
        .where.not(currency:)
        .exists?
    end
  end
end
