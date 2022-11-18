# frozen_string_literal: true

module V1
  class OrganizationSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        created_at: model.created_at.iso8601,
        webhook_url: model.webhook_url,
        country: model.country,
        address_line1: model.address_line1,
        address_line2: model.address_line2,
        state: model.state,
        zipcode: model.zipcode,
        email: model.email,
        city: model.city,
        legal_name: model.legal_name,
        legal_number: model.legal_number,
        billing_configuration: {
          invoice_footer: model.invoice_footer,
          invoice_grace_period: model.invoice_grace_period,
          vat_rate: model.vat_rate,
        },
      }
    end
  end
end
