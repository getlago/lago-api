# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::TaxSerializer do
  subject(:payload) { described_class.new(tax, includes:).serialize }

  let(:tax) { build_stubbed(:tax, deleted_at:) }
  let(:deleted_at) { nil }
  let(:includes) { [] }

  it "renders the tax without counts nor deleted_at" do
    expect(payload).to eq(
      lago_id: tax.id,
      name: tax.name,
      code: tax.code,
      rate: tax.rate,
      description: tax.description,
      applied_to_organization: tax.applied_to_organization,
      created_at: tax.created_at.iso8601
    )
  end

  # What the activity log gets through the rate card: its taxes must keep the V1 shape.
  context "with counts" do
    let(:includes) { %i[counts] }
    let(:v1_payload) { V1::TaxSerializer.new(tax).serialize }

    it "renders the V1 payload, in the same key order" do
      expect(payload).to eq(v1_payload)
      expect(payload.keys).to eq(v1_payload.keys)
    end
  end

  context "with deleted_at" do
    let(:includes) { %i[deleted_at] }
    let(:deleted_at) { Time.zone.parse("2026-09-30T12:00:00Z") }

    it "renders deleted_at last, without counts" do
      expect(payload.keys).to eq(%i[lago_id name code rate description applied_to_organization created_at deleted_at])
      expect(payload[:deleted_at]).to eq("2026-09-30T12:00:00Z")
    end
  end
end
