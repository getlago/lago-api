# frozen_string_literal: true

module BillingEntities
  class ValidateApiInputService < BaseService
    Result = BaseResult

    ENUMS = {
      document_numbering: BillingEntity::DOCUMENT_NUMBERINGS,
      subscription_invoice_issuing_date_anchor: BillingEntity::SUBSCRIPTION_INVOICE_ISSUING_DATE_ANCHORS,
      subscription_invoice_issuing_date_adjustment: BillingEntity::SUBSCRIPTION_INVOICE_ISSUING_DATE_ADJUSTMENTS
    }.freeze

    def initialize(params:, require_code: false)
      @params = params
      @require_code = require_code
      super
    end

    def call
      attributes = params.slice(:document_numbering).merge(params[:billing_configuration] || {})
      errors = ENUMS.each_with_object({}) do |(field, values), invalid|
        if attributes.key?(field) && !values.value?(attributes[field])
          invalid[field] = ["value_is_invalid"]
        end
      end

      if require_code && params[:code].blank?
        errors[:code] = ["value_is_mandatory"]
      end

      if params.key?(:tax_codes) && !params[:tax_codes].all?(String)
        errors[:tax_codes] = ["value_is_invalid"]
      end

      if params.key?(:eu_tax_management) && ![true, false].include?(params[:eu_tax_management])
        errors[:eu_tax_management] = ["value_is_invalid"]
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
