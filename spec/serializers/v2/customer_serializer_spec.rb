# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::CustomerSerializer do
  subject(:payload) { described_class.new(customer, includes:).serialize }

  let(:organization) { build_stubbed(:organization, feature_flags:) }
  let(:feature_flags) { [] }
  let(:billing_entity) { build_stubbed(:billing_entity, organization:, code: "acme_eu", timezone: "America/New_York") }
  let(:customer) do
    build_stubbed(
      :customer,
      organization:,
      billing_entity:,
      external_id: "cus_001",
      account_type: "customer",
      name: "Acme",
      firstname: "Ada",
      lastname: "Lovelace",
      customer_type: "company",
      sequential_id: 7,
      slug: "LAG-1234-007",
      created_at: Time.zone.parse("2026-09-01T08:00:00Z"),
      updated_at: Time.zone.parse("2026-09-02T09:00:00Z"),
      country: "FR",
      address_line1: "1 rue de la Paix",
      address_line2: "Bâtiment B",
      state: "Île-de-France",
      zipcode: "75002",
      email: "billing@acme.test",
      city: "Paris",
      url: "https://acme.test",
      phone: "+33100000000",
      logo_url: "https://acme.test/logo.png",
      legal_name: "Acme SAS",
      legal_number: "123456789",
      currency: "EUR",
      tax_identification_number: "FR12345678901",
      timezone: nil,
      net_payment_term: 30,
      external_salesforce_id: "sf_001",
      finalize_zero_amount_invoice: "skip",
      skip_invoice_custom_sections: true,
      x402_agent_address: "0x1111111111111111111111111111111111111111",
      deleted_at:
    )
  end
  let(:includes) { [] }
  let(:deleted_at) { nil }
  let(:expected_payload) do
    {
      lago_id: customer.id,
      billing_entity_code: "acme_eu",
      external_id: "cus_001",
      account_type: "customer",
      name: "Acme",
      firstname: "Ada",
      lastname: "Lovelace",
      customer_type: "company",
      sequential_id: 7,
      slug: "LAG-1234-007",
      created_at: "2026-09-01T08:00:00Z",
      updated_at: "2026-09-02T09:00:00Z",
      country: "FR",
      address_line1: "1 rue de la Paix",
      address_line2: "Bâtiment B",
      state: "Île-de-France",
      zipcode: "75002",
      email: "billing@acme.test",
      city: "Paris",
      url: "https://acme.test",
      phone: "+33100000000",
      logo_url: "https://acme.test/logo.png",
      legal_name: "Acme SAS",
      legal_number: "123456789",
      currency: "EUR",
      tax_identification_number: "FR12345678901",
      timezone: nil,
      applicable_timezone: "America/New_York",
      external_salesforce_id: "sf_001",
      finalize_zero_amount_invoice: "skip",
      skip_invoice_custom_sections: true,
      invoice_grace_period: customer.invoice_grace_period,
      subscription_invoice_issuing_date_anchor: customer.subscription_invoice_issuing_date_anchor,
      subscription_invoice_issuing_date_adjustment: customer.subscription_invoice_issuing_date_adjustment,
      payment_provider: nil,
      payment_provider_code: nil,
      provider_customer_id: nil,
      provider_payment_methods: nil,
      document_locale: customer.document_locale,
      deleted_at: nil
    }
  end

  it "renders flat billing fields without payment terms or nested objects" do
    expect(payload).to eq(expected_payload)
    expect(payload.keys).to eq(expected_payload.keys)
  end

  it "keeps the other scalar fields of V1" do
    excluded = %i[billing_configuration shipping_address metadata net_payment_term]
    v1_payload = V1::CustomerSerializer.new(customer).serialize.except(*excluded)

    expect(payload.slice(*v1_payload.keys)).to eq(v1_payload)
  end

  context "with shipping details for the customer endpoint" do
    let(:includes) { [:shipping_address] }

    it "includes the nested shipping address" do
      expect(payload).to eq(expected_payload.merge(shipping_address: customer.shipping_address))
    end
  end

  context "when the organization takes x402 payments", :premium do
    let(:feature_flags) { ["x402_payments"] }

    it "renders the agent address after the other fields, as V1 does" do
      expect(payload.keys).to eq([*expected_payload.keys.excluding(:deleted_at), :x402_agent_address, :deleted_at])
      expect(payload).to eq(expected_payload.merge(x402_agent_address: "0x1111111111111111111111111111111111111111"))
    end
  end

  context "when the organization has the x402 flag without a premium license" do
    let(:feature_flags) { ["x402_payments"] }

    it "leaves the agent address out, as V1 does" do
      expect(payload).to eq(expected_payload)
    end
  end

  context "when the customer is discarded" do
    let(:deleted_at) { Time.zone.parse("2026-09-30T12:00:00Z") }

    it "renders its deleted_at" do
      expect(payload).to eq(expected_payload.merge(deleted_at: "2026-09-30T12:00:00Z"))
    end
  end

  context "with expansions" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:includes) { %i[metadata taxes integration_customers] }
    let(:metadata) { create(:customer_metadata, customer:, display_in_invoice: false) }
    let(:tax) { create(:tax, organization:) }

    before do
      metadata
      create(:customer_applied_tax, customer:, tax:)
    end

    it "uses the v2 metadata name and omits tax assignment counts" do
      expect(payload[:metadata]).to eq([{
        lago_id: metadata.id,
        key: metadata.key,
        value: metadata.value,
        display_on_invoice: false,
        created_at: metadata.created_at.iso8601,
        updated_at: metadata.updated_at.iso8601
      }])
      expect(payload[:taxes]).to eq([{
        lago_id: tax.id,
        name: tax.name,
        code: tax.code,
        rate: tax.rate,
        description: tax.description,
        created_at: tax.created_at.iso8601,
        updated_at: tax.updated_at.iso8601,
        deleted_at: nil
      }])
      expect(payload[:integration_customers]).to eq([])
    end
  end

  context "with a payment provider" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, :with_stripe_payment_provider, organization:) }

    it "includes its customer id and payment methods at the top level" do
      expect(payload).to include(
        payment_provider: "stripe",
        payment_provider_code: customer.payment_provider_code,
        provider_customer_id: customer.stripe_customer.provider_customer_id,
        provider_payment_methods: customer.stripe_customer.provider_payment_methods
      )
      expect(payload).not_to have_key(:billing_configuration)
    end
  end
end
