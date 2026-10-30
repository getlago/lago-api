# frozen_string_literal: true

module V2
  class BillingEntitySerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    expandable :taxes, serializer: ::V2::TaxSerializer
    expandable :selected_invoice_custom_sections, serializer: ::V2::InvoiceCustomSectionSerializer

    def serialize
      model.slice(
        :code, :name, :default_currency, :country, :address_line1, :address_line2,
        :phone, :city, :state, :zipcode, :einvoicing, :email, :legal_name, :legal_number,
        :timezone, :email_settings, :document_numbering, :document_number_prefix,
        :tax_identification_number, :finalize_zero_amount_invoice, :invoice_footer,
        :invoice_grace_period, :document_locale, :eu_tax_management
      ).symbolize_keys.merge(
        periodic_invoice_issuing_date_anchor: model.subscription_invoice_issuing_date_anchor,
        periodic_invoice_issuing_date_adjustment: model.subscription_invoice_issuing_date_adjustment,
        lago_id: model.id,
        is_default: model.organization.default_billing_entity&.id == model.id,
        logo_url: model.logo_url,
        archived_at: format_time(model.archived_at)
      )
    end

    private

    def taxes = model.taxes.order(:created_at, :id)

    def selected_invoice_custom_sections = model.selected_invoice_custom_sections.order(:created_at, :id)
  end
end
