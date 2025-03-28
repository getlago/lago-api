# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::BillingEntitySerializer, type: :serializer do
  subject(:serializer) { described_class.new(billing_entity, root_name: "billing_entity") }

  let(:billing_entity) { create(:billing_entity) }
  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the billing entity" do
    expect(result["billing_entity"]["lago_id"]).to eq(billing_entity.id)
    expect(result["billing_entity"]["code"]).to eq(billing_entity.code)
    expect(result["billing_entity"]["name"]).to eq(billing_entity.name)
    expect(result["billing_entity"]["default_currency"]).to eq(billing_entity.default_currency)
    expect(result["billing_entity"]["created_at"]).to eq(billing_entity.created_at.iso8601)
    expect(result["billing_entity"]["updated_at"]).to eq(billing_entity.updated_at.iso8601)
    expect(result["billing_entity"]["country"]).to eq(billing_entity.country)
    expect(result["billing_entity"]["address_line1"]).to eq(billing_entity.address_line1)
    expect(result["billing_entity"]["address_line2"]).to eq(billing_entity.address_line2)
    expect(result["billing_entity"]["city"]).to eq(billing_entity.city)
    expect(result["billing_entity"]["state"]).to eq(billing_entity.state)
    expect(result["billing_entity"]["zipcode"]).to eq(billing_entity.zipcode)
    expect(result["billing_entity"]["email"]).to eq(billing_entity.email)
    expect(result["billing_entity"]["legal_name"]).to eq(billing_entity.legal_name)
    expect(result["billing_entity"]["legal_number"]).to eq(billing_entity.legal_number)
    expect(result["billing_entity"]["timezone"]).to eq(billing_entity.timezone)
    expect(result["billing_entity"]["net_payment_term"]).to eq(billing_entity.net_payment_term)
    expect(result["billing_entity"]["email_settings"]).to eq(billing_entity.email_settings)
    expect(result["billing_entity"]["document_numbering"]).to eq(billing_entity.document_numbering)
    expect(result["billing_entity"]["document_number_prefix"]).to eq(billing_entity.document_number_prefix)
    expect(result["billing_entity"]["tax_identification_number"]).to eq(billing_entity.tax_identification_number)
    expect(result["billing_entity"]["finalize_zero_amount_invoice"]).to eq(billing_entity.finalize_zero_amount_invoice)
    expect(result["billing_entity"]["billing_configuration"]).to match(hash_including(
      "invoice_footer" => billing_entity.invoice_footer,
      "invoice_grace_period" => billing_entity.invoice_grace_period,
      "document_locale" => billing_entity.document_locale
    ))
  end
end
