# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::TaxSerializer do
  subject(:payload) { described_class.new(tax).serialize }

  let(:tax) { build_stubbed(:tax, applied_to_organization: true, deleted_at:) }
  let(:deleted_at) { nil }
  let(:expected_payload) do
    {
      lago_id: tax.id,
      name: tax.name,
      code: tax.code,
      rate: tax.rate,
      description: tax.description,
      created_at: tax.created_at.iso8601,
      deleted_at: nil
    }
  end

  it "renders the tax without applied_to_organization nor counts" do
    expect(payload).to eq(expected_payload)
  end

  context "when the tax is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-09-30T12:00:00Z") }

    it "renders its deletion date" do
      expect(payload).to eq(expected_payload.merge(deleted_at: "2026-09-30T12:00:00Z"))
    end
  end
end
