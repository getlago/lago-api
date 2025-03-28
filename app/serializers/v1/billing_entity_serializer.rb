# frozen_string_literal: true

module V1
  class BillingEntitySerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        name: model.name,
        default_currency: model.default_currency,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        country: model.country,
        address_line1: model.address_line1,
        address_line2: model.address_line2,
        city: model.city,
        state: model.state,
        zipcode: model.zipcode,
        email: model.email,
        legal_name: model.legal_name,
        legal_number: model.legal_number,
        timezone: model.timezone,
        net_payment_term: model.net_payment_term,
        email_settings: model.email_settings,
        document_numbering: model.document_numbering,
        document_number_prefix: model.document_number_prefix,
        tax_identification_number: model.tax_identification_number,
        finalize_zero_amount_invoice: model.finalize_zero_amount_invoice,
        billing_configuration:
      }
    end

    private

    def billing_configuration
      {
        invoice_footer: model.invoice_footer,
        invoice_grace_period: model.invoice_grace_period,
        document_locale: model.document_locale
      }
    end
  end
end
