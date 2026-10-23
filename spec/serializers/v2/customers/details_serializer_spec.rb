# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::Customers::DetailsSerializer do
  subject(:payload) { described_class.new(customer).serialize }

  let(:customer) { build_stubbed(:customer, :with_shipping_address, net_payment_term: 30) }

  it "includes the customer fields and shipping address without relationships" do
    expect(payload).to eq(
      lago_id: customer.id,
      external_id: customer.external_id,
      billing_entity_code: customer.billing_entity.code,
      account_type: customer.account_type,
      name: customer.name,
      firstname: customer.firstname,
      lastname: customer.lastname,
      customer_type: customer.customer_type,
      sequential_id: customer.sequential_id,
      slug: customer.slug,
      country: customer.country,
      address_line1: customer.address_line1,
      address_line2: customer.address_line2,
      state: customer.state,
      zipcode: customer.zipcode,
      email: customer.email,
      city: customer.city,
      url: customer.url,
      phone: customer.phone,
      logo_url: customer.logo_url,
      legal_name: customer.legal_name,
      legal_number: customer.legal_number,
      currency: customer.currency,
      tax_identification_number: customer.tax_identification_number,
      timezone: customer.timezone,
      applicable_timezone: customer.applicable_timezone,
      external_salesforce_id: customer.external_salesforce_id,
      finalize_zero_amount_invoice: customer.finalize_zero_amount_invoice,
      skip_invoice_custom_sections: customer.skip_invoice_custom_sections,
      invoice_grace_period: customer.invoice_grace_period,
      subscription_invoice_issuing_date_anchor: customer.subscription_invoice_issuing_date_anchor,
      subscription_invoice_issuing_date_adjustment: customer.subscription_invoice_issuing_date_adjustment,
      payment_provider: nil,
      payment_provider_code: nil,
      provider_customer_id: nil,
      provider_payment_methods: nil,
      document_locale: customer.document_locale,
      shipping_address: {
        address_line1: customer.shipping_address_line1,
        address_line2: customer.shipping_address_line2,
        city: customer.shipping_city,
        zipcode: customer.shipping_zipcode,
        state: customer.shipping_state,
        country: customer.shipping_country
      },
      created_at: customer.created_at.iso8601,
      updated_at: customer.updated_at.iso8601,
      deleted_at: nil
    )
  end
end
