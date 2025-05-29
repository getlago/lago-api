# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::CustomerSerializer do
  subject(:serializer) do
    described_class.new(customer, root_name: "customer", includes: %i[taxes integration_customers applicable_invoice_custom_sections])
  end

  let(:result) { JSON.parse(serializer.to_json) }
  let(:organization) { customer.organization }
  let(:billing_entity) { customer.billing_entity }
  let(:customer) { create(:customer, :with_salesforce_integration, shipping_city: "Paris", shipping_address_line1: "test1", shipping_zipcode: "002") }
  let(:metadata) { create(:customer_metadata, customer:) }
  let(:tax) { create(:tax, organization: customer.organization) }
  let(:customer_applied_tax) { create(:customer_applied_tax, customer:, tax:) }
  let(:invoice_custom_section) { create(:invoice_custom_section, organization:) }

  before do
    metadata
    customer_applied_tax
    create(:customer_applied_invoice_custom_section, organization:, billing_entity:, customer:, invoice_custom_section:)
  end

  it "serializes the object" do
    expect(result["customer"]["lago_id"]).to eq(customer.id)
    expect(result["customer"]["billing_entity_code"]).to eq(customer.billing_entity.code)
    expect(result["customer"]["external_id"]).to eq(customer.external_id)
    expect(result["customer"]["account_type"]).to eq(customer.account_type)
    expect(result["customer"]["name"]).to eq(customer.name)
    expect(result["customer"]["firstname"]).to eq(customer.firstname)
    expect(result["customer"]["lastname"]).to eq(customer.lastname)
    expect(result["customer"]["customer_type"]).to eq(customer.customer_type)
    expect(result["customer"]["sequential_id"]).to eq(customer.sequential_id)
    expect(result["customer"]["slug"]).to eq(customer.slug)
    expect(result["customer"]["created_at"]).to eq(customer.created_at.iso8601)
    expect(result["customer"]["updated_at"]).to eq(customer.updated_at.iso8601)
    expect(result["customer"]["country"]).to eq(customer.country)
    expect(result["customer"]["address_line1"]).to eq(customer.address_line1)
    expect(result["customer"]["address_line2"]).to eq(customer.address_line2)
    expect(result["customer"]["state"]).to eq(customer.state)
    expect(result["customer"]["zipcode"]).to eq(customer.zipcode)
    expect(result["customer"]["email"]).to eq(customer.email)
    expect(result["customer"]["city"]).to eq(customer.city)
    expect(result["customer"]["url"]).to eq(customer.url)
    expect(result["customer"]["phone"]).to eq(customer.phone)
    expect(result["customer"]["logo_url"]).to eq(customer.logo_url)
    expect(result["customer"]["legal_name"]).to eq(customer.legal_name)
    expect(result["customer"]["legal_number"]).to eq(customer.legal_number)
    expect(result["customer"]["currency"]).to eq(customer.currency)
    expect(result["customer"]["timezone"]).to eq(customer.timezone)
    expect(result["customer"]["applicable_timezone"]).to eq(customer.applicable_timezone)
    expect(result["customer"]["net_payment_term"]).to eq(customer.net_payment_term)
    expect(result["customer"]["finalize_zero_amount_invoice"]).to eq(customer.finalize_zero_amount_invoice)
    expect(result["customer"]["billing_configuration"]["payment_provider"]).to eq(customer.payment_provider)
    expect(result["customer"]["billing_configuration"]["payment_provider_code"]).to eq(customer.payment_provider_code)
    expect(result["customer"]["billing_configuration"]["invoice_grace_period"]).to eq(customer.invoice_grace_period)
    expect(result["customer"]["billing_configuration"]["document_locale"]).to eq(customer.document_locale)
    expect(result["customer"]["shipping_address"]["address_line1"]).to eq("test1")
    expect(result["customer"]["shipping_address"]["city"]).to eq("Paris")
    expect(result["customer"]["shipping_address"]["zipcode"]).to eq("002")
    expect(result["customer"]["metadata"].first["lago_id"]).to eq(metadata.id)
    expect(result["customer"]["metadata"].first["key"]).to eq(metadata.key)
    expect(result["customer"]["metadata"].first["value"]).to eq(metadata.value)
    expect(result["customer"]["metadata"].first["display_in_invoice"]).to eq(metadata.display_in_invoice)
    expect(result["customer"]["tax_identification_number"]).to eq(customer.tax_identification_number)
    expect(result["customer"]["taxes"].count).to eq(1)
    expect(result["customer"]["integration_customers"].count).to eq(1)
    expect(result["customer"]["applicable_invoice_custom_sections"].count).to eq(1)
    expect(result["customer"]["skip_invoice_custom_sections"]).to eq(false)
  end

  context "with a stripe customer" do
    let(:stripe_customer) { create(:stripe_customer, customer:) }

    before do
      stripe_customer
      customer.update!(payment_provider: "stripe")
    end

    it "serializes the object" do
      expect(result["customer"]["billing_configuration"]["provider_customer_id"]).to eq(stripe_customer.provider_customer_id)
      expect(result["customer"]["billing_configuration"]["provider_payment_methods"]).to eq(stripe_customer.provider_payment_methods)
    end
  end

  context "with a VIES check" do
    subject(:serializer) { described_class.new(customer, root_name: "customer", includes: %i[vies_check], vies_check: {custom_hash: "yes"}) }

    let(:customer) { create(:customer, :with_salesforce_integration, tax_identification_number: "IT12345678901") }

    it "adds vies_check to customer" do
      expect(result["customer"]["vies_check"]).to eq({"custom_hash" => "yes"})
    end
  end
end
