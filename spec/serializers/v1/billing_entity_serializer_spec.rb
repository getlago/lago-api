# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::BillingEntitySerializer, type: :serializer do
  subject(:serializer) { described_class.new(billing_entity, root_name: "billing_entity") }

  let(:billing_entity) { create(:billing_entity) }
  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the billing entity" do
    billing_entity_serialized = result["billing_entity"]
    expect(billing_entity_serialized.fetch("lago_id")).to eq(billing_entity.id)
    expect(billing_entity_serialized.fetch("code")).to eq(billing_entity.code)
    expect(billing_entity_serialized.fetch("name")).to eq(billing_entity.name)
    expect(billing_entity_serialized.fetch("default_currency")).to eq(billing_entity.default_currency)
    expect(billing_entity_serialized.fetch("created_at")).to eq(billing_entity.created_at.iso8601)
    expect(billing_entity_serialized.fetch("updated_at")).to eq(billing_entity.updated_at.iso8601)
    expect(billing_entity_serialized.fetch("country")).to eq(billing_entity.country)
    expect(billing_entity_serialized.fetch("address_line1")).to eq(billing_entity.address_line1)
    expect(billing_entity_serialized.fetch("address_line2")).to eq(billing_entity.address_line2)
    expect(billing_entity_serialized.fetch("city")).to eq(billing_entity.city)
    expect(billing_entity_serialized.fetch("state")).to eq(billing_entity.state)
    expect(billing_entity_serialized.fetch("zipcode")).to eq(billing_entity.zipcode)
    expect(billing_entity_serialized.fetch("email")).to eq(billing_entity.email)
    expect(billing_entity_serialized.fetch("legal_name")).to eq(billing_entity.legal_name)
    expect(billing_entity_serialized.fetch("legal_number")).to eq(billing_entity.legal_number)
    expect(billing_entity_serialized.fetch("timezone")).to eq(billing_entity.timezone)
    expect(billing_entity_serialized.fetch("net_payment_term")).to eq(billing_entity.net_payment_term)
    expect(billing_entity_serialized.fetch("email_settings")).to eq(billing_entity.email_settings)
    expect(billing_entity_serialized.fetch("document_numbering")).to eq(billing_entity.document_numbering)
    expect(billing_entity_serialized.fetch("document_number_prefix")).to eq(billing_entity.document_number_prefix)
    expect(billing_entity_serialized.fetch("tax_identification_number")).to eq(billing_entity.tax_identification_number)
    expect(billing_entity_serialized.fetch("finalize_zero_amount_invoice")).to eq(billing_entity.finalize_zero_amount_invoice)
    expect(billing_entity_serialized.fetch("invoice_footer")).to eq(billing_entity.invoice_footer)
    expect(billing_entity_serialized.fetch("invoice_grace_period")).to eq(billing_entity.invoice_grace_period)
    expect(billing_entity_serialized.fetch("document_locale")).to eq(billing_entity.document_locale)
    expect(billing_entity_serialized.fetch("is_default")).to eq(billing_entity.organization.default_billing_entity.id == billing_entity.id)
  end
end
