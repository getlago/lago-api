# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::InvoiceCustomSectionSerializer do
  subject(:payload) { described_class.new(section).serialize }

  let(:section) do
    build_stubbed(
      :invoice_custom_section,
      code: "eu_bank_details",
      name: "EU bank details",
      description: "Where EU customers pay",
      details: "Pay to the account below",
      display_name: "Bank details",
      created_at: Time.zone.parse("2026-09-01T08:00:00Z"),
      updated_at: Time.zone.parse("2026-09-02T09:00:00Z"),
      deleted_at:
    )
  end
  let(:deleted_at) { nil }
  let(:expected_payload) do
    {
      lago_id: section.id,
      code: "eu_bank_details",
      name: "EU bank details",
      description: "Where EU customers pay",
      details: "Pay to the account below",
      display_name: "Bank details",
      created_at: "2026-09-01T08:00:00Z",
      updated_at: "2026-09-02T09:00:00Z",
      deleted_at: nil
    }
  end

  it "serializes the section" do
    expect(payload).to eq(expected_payload)
  end

  it "renders the fields of V1 without the organization, then the timestamps" do
    expect(payload.except(:created_at, :updated_at, :deleted_at)).to eq(
      V1::InvoiceCustomSectionSerializer.new(section).serialize.except(:organization_id)
    )
    expect(payload.keys.last(3)).to eq(%i[created_at updated_at deleted_at])
  end

  context "when the section is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-10-05T10:00:00Z") }

    it "renders its deleted_at" do
      expect(payload).to eq(expected_payload.merge(deleted_at: "2026-10-05T10:00:00Z"))
    end
  end
end
