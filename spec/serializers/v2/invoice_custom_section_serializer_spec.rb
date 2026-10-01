# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::InvoiceCustomSectionSerializer do
  subject(:payload) { described_class.new(section, includes:).serialize }

  let(:section) { build_stubbed(:invoice_custom_section, deleted_at:) }
  let(:includes) { [] }
  let(:deleted_at) { nil }

  it "renders the fields of V1, without the organization, plus the timestamps" do
    expect(payload).to eq(
      **V1::InvoiceCustomSectionSerializer.new(section).serialize.except(:organization_id),
      created_at: section.created_at.iso8601,
      updated_at: section.updated_at.iso8601
    )
  end

  context "with deleted_at" do
    let(:includes) { %i[deleted_at] }
    let(:deleted_at) { Time.zone.parse("2026-10-05T10:00:00Z") }

    it "renders it last" do
      expect(payload.keys).to eq(%i[lago_id code name description details display_name created_at updated_at deleted_at])
      expect(payload[:deleted_at]).to eq("2026-10-05T10:00:00Z")
    end
  end
end
