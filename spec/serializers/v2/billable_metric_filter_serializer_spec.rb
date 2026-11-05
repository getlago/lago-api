# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::BillableMetricFilterSerializer do
  subject(:payload) { described_class.new(filter, includes:).serialize }

  let(:filter) { build_stubbed(:billable_metric_filter, key: "region", values: %w[us eu], deleted_at:) }
  let(:deleted_at) { nil }
  let(:includes) { [] }
  let(:precision) { 0 }
  let(:expected_payload) do
    {
      lago_id: filter.id,
      key: "region",
      values: %w[eu us],
      created_at: filter.created_at.iso8601(precision),
      updated_at: filter.updated_at.iso8601(precision),
      deleted_at: deleted_at&.iso8601(precision)
    }
  end

  it "returns the filter with sorted values and timestamps" do
    expect(payload).to eq(expected_payload)
  end

  context "with microsecond timestamps" do
    let(:includes) { %i[usec_timestamps] }
    let(:precision) { 6 }

    it "preserves timestamp precision" do
      expect(payload).to eq(expected_payload)
    end
  end

  context "when the filter is discarded" do
    let(:deleted_at) { Time.zone.parse("2026-10-01T10:00:00Z") }

    it "includes its deletion timestamp" do
      expect(payload).to eq(expected_payload)
    end
  end
end
