# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::Entitlement::FeatureSerializer do
  subject(:payload) { described_class.new(feature, includes:).serialize }

  let(:feature) do
    build_stubbed(
      :feature,
      code: "seats",
      name: "Seats",
      description: "Number of seats",
      created_at: Time.zone.parse("2026-03-02T10:00:00.123456Z"),
      updated_at: Time.zone.parse("2026-03-04T12:30:00.654321Z"),
      deleted_at:
    )
  end
  let(:deleted_at) { nil }
  let(:includes) { [] }
  let(:expected_payload) do
    {
      lago_id: feature.id,
      code: "seats",
      name: "Seats",
      description: "Number of seats",
      created_at: "2026-03-02T10:00:00Z",
      updated_at: "2026-03-04T12:30:00Z",
      deleted_at: nil
    }
  end

  it "renders the feature with whole-second timestamps" do
    expect(payload).to eq(expected_payload)
  end

  context "with microsecond timestamps" do
    let(:includes) { %i[usec_timestamps] }

    it "renders the timestamps to the microsecond" do
      expect(payload).to eq(expected_payload.merge(
        created_at: "2026-03-02T10:00:00.123456Z",
        updated_at: "2026-03-04T12:30:00.654321Z"
      ))
    end
  end

  context "with privileges" do
    let(:feature) { create(:feature, code: "seats", name: "Seats", description: "Number of seats") }
    let(:expected_payload) do
      {
        lago_id: feature.id,
        code: "seats",
        name: "Seats",
        description: "Number of seats",
        created_at: feature.created_at.iso8601,
        updated_at: feature.updated_at.iso8601,
        deleted_at: nil
      }
    end

    before { create(:privilege, feature:, organization: feature.organization) }

    it "renders neither the privileges nor a count of them" do
      expect(payload).to eq(expected_payload)
    end
  end

  context "when the feature is discarded" do
    let(:deleted_at) { Time.zone.parse("2026-03-05T08:15:00Z") }

    it "renders its deletion timestamp" do
      expect(payload).to eq(expected_payload.merge(deleted_at: "2026-03-05T08:15:00Z"))
    end
  end
end
