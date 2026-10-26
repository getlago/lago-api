# frozen_string_literal: true

module BillingEntities
  class ValidateApiInputService < BaseService
    Result = BaseResult

    # Allowed values per stored attribute, with the REST field an error is reported under.
    ENUMS = {
      document_numbering: [:document_numbering, BillingEntity::DOCUMENT_NUMBERINGS],
      subscription_invoice_issuing_date_anchor: [:periodic_invoice_issuing_date_anchor, BillingEntity::SUBSCRIPTION_INVOICE_ISSUING_DATE_ANCHORS],
      subscription_invoice_issuing_date_adjustment: [:periodic_invoice_issuing_date_adjustment, BillingEntity::SUBSCRIPTION_INVOICE_ISSUING_DATE_ADJUSTMENTS]
    }.freeze

    def initialize(params:, require_code: false)
      @params = params
      @require_code = require_code
      super
    end

    def call
      attributes = params.slice(:document_numbering).merge(params[:billing_configuration] || {})
      errors = ENUMS.each_with_object({}) do |(attribute, (field, values)), invalid|
        if attributes.key?(attribute) && !values.value?(attributes[attribute])
          invalid[field] = ["value_is_invalid"]
        end
      end

      if require_code && params[:code].blank?
        errors[:code] = ["value_is_mandatory"]
      end

      if params.key?(:tax_codes) && !params[:tax_codes].all?(String)
        errors[:tax_codes] = ["value_is_invalid"]
      end

      %i[eu_tax_management einvoicing finalize_zero_amount_invoice].each do |field|
        errors[field] = ["value_is_invalid"] if params.key?(field) && ![true, false].include?(params[field])
      end

      if params[:logo].present? && (!params[:logo].is_a?(String) || !params[:logo].match?(%r{\Adata:image/(png|jpe?g);base64,[A-Za-z0-9+/=\s]+\z}))
        errors[:logo] = ["value_is_invalid"]
      end

      result.validation_failure!(errors:) if errors.any?
      result
    end

    private

    attr_reader :params, :require_code
  end
end
