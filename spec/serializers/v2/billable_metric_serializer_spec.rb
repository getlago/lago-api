# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::BillableMetricSerializer do
  subject(:payload) { described_class.new(billable_metric, includes:).serialize }

  let(:billable_metric) do
    build_stubbed(
      :weighted_sum_billable_metric,
      recurring: true,
      rounding_function: "round",
      rounding_precision: 2,
      expression: "round(event.properties.value)",
      deleted_at:
    )
  end
  let(:deleted_at) { nil }
  let(:includes) { [] }
  let(:scalar_payload) do
    {
      lago_id: billable_metric.id,
      name: billable_metric.name,
      code: billable_metric.code,
      description: billable_metric.description,
      aggregation_type: "weighted_sum_agg",
      weighted_interval: "seconds",
      recurring: true,
      rounding_function: "round",
      rounding_precision: 2,
      created_at: billable_metric.created_at.iso8601,
      field_name: "value",
      expression: "round(event.properties.value)"
    }
  end

  it "renders the scalar fields of V1, without filters nor counters" do
    expect(payload).to eq(scalar_payload)
  end

  it "renders scalar values only" do
    expect(payload.values).to all(be_a(String).or(be_a(Integer)).or(be(true)).or(be(false)))
  end

  # V1 adds its counters with this option, and its filters always.
  context "with V1's counters option" do
    let(:includes) { %i[counters] }

    it "renders the same payload as without options" do
      expect(payload).to eq(scalar_payload)
    end
  end

  context "with deleted_at" do
    let(:includes) { %i[deleted_at] }
    let(:deleted_at) { Time.zone.parse("2026-09-30T12:00:00Z") }

    it "renders deleted_at last" do
      expect(payload.keys).to eq([*scalar_payload.keys, :deleted_at])
      expect(payload[:deleted_at]).to eq("2026-09-30T12:00:00Z")
    end
  end
end
