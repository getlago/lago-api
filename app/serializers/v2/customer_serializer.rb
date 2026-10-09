# frozen_string_literal: true

module V2
  # V1's scalar fields only: billing_configuration, shipping_address, metadata and everything V1
  # includes on demand are left out, so the record stays flat.
  class CustomerSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        billing_entity_code: model.billing_entity.code,
        external_id: model.external_id,
        account_type: model.account_type,
        name: model.name,
        firstname: model.firstname,
        lastname: model.lastname,
        customer_type: model.customer_type,
        sequential_id: model.sequential_id,
        slug: model.slug,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        country: model.country,
        address_line1: model.address_line1,
        address_line2: model.address_line2,
        state: model.state,
        zipcode: model.zipcode,
        email: model.email,
        city: model.city,
        url: model.url,
        phone: model.phone,
        logo_url: model.logo_url,
        legal_name: model.legal_name,
        legal_number: model.legal_number,
        currency: model.currency,
        tax_identification_number: model.tax_identification_number,
        timezone: model.timezone,
        applicable_timezone: model.applicable_timezone,
        net_payment_term: model.net_payment_term,
        external_salesforce_id: model.external_salesforce_id,
        finalize_zero_amount_invoice: model.finalize_zero_amount_invoice,
        skip_invoice_custom_sections: model.skip_invoice_custom_sections,
        **deleted_at_payload
      }
    end
  end
end
