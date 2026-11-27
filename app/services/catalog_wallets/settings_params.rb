# frozen_string_literal: true

module CatalogWallets
  module SettingsParams
    include Metadata::ReplaceItemParams

    ATTRIBUTES = %i[
      code name invoice_display_name currency tax_application priority top_up_min_amount_cents top_up_max_amount_cents
    ].freeze
    RELATED_PARAMS = %i[metadata tax_codes applies_to].freeze

    private

    def unknown_tax_application_failure
      result.single_validation_failure!(
        field: :tax_application,
        error_code: "value_is_invalid",
        meta: {allowed_values: CatalogWalletSettings::TAX_APPLICATIONS.values}
      )
    end

    def known_tax_application?
      CatalogWalletSettings::TAX_APPLICATIONS.value?(params[:tax_application])
    end

    # The field whose value has another shape than its service reads: a metadata object, a list of tax codes.
    def malformed_param
      if malformed_metadata?(params[:metadata])
        :metadata
      elsif !params[:tax_codes].nil? && !(params[:tax_codes].is_a?(Array) && params[:tax_codes].all?(String))
        :tax_codes
      end
    end

    def replace_taxes_and_scope!(wallet)
      CatalogWallets::ApplyTaxesService.call!(wallet:, tax_codes: params[:tax_codes]) unless params[:tax_codes].nil?
      CatalogWalletSelectors::ReplaceService.call!(wallet:, applies_to: params[:applies_to]) unless params[:applies_to].nil?
    end
  end
end
