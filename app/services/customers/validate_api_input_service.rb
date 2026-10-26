# frozen_string_literal: true

module Customers
  class ValidateApiInputService < BaseService
    Result = BaseResult

    # Settings stored under another name than their REST field, with their allowed values.
    ISSUING_DATE_SETTINGS = {
      subscription_invoice_issuing_date_anchor: [:periodic_invoice_anchor, Customer::SUBSCRIPTION_INVOICE_ISSUING_DATE_ANCHORS],
      subscription_invoice_issuing_date_adjustment: [:periodic_invoice_adjustment, Customer::SUBSCRIPTION_INVOICE_ISSUING_DATE_ADJUSTMENTS]
    }.freeze

    def initialize(params:)
      @params = params
      super
    end

    def call
      value = params[:finalize_zero_amount_invoice]
      if !value.nil? && (!value.is_a?(String) || !Customer::FINALIZE_ZERO_AMOUNT_INVOICE_OPTIONS.include?(value.to_sym))
        return result.single_validation_failure!(field: :finalize_zero_amount_invoice, error_code: "invalid_value")
      end

      # Validated here so that the error names the REST field, not the column it is stored in.
      ISSUING_DATE_SETTINGS.each do |setting, (field, allowed_values)|
        value = params.dig(:billing_configuration, setting)
        if !value.nil? && !allowed_values.value?(value)
          return result.single_validation_failure!(field:, error_code: "value_is_invalid")
        end
      end

      integration_types = params[:integration_customers]&.map { |entry| entry[:integration_type] } || []
      if integration_types.uniq.size != integration_types.size
        return result.single_validation_failure!(field: :integration_customers, error_code: "invalid_count_per_integration_type")
      end

      result
    end

    private

    attr_reader :params
  end
end
