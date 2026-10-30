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
      created_at: Time.zone.parse("2026-01-05T10:00:00Z"),
      updated_at: Time.zone.parse("2026-01-06T11:30:00Z"),
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
      created_at: "2026-01-05T10:00:00Z",
      field_name: "value",
      expression: "round(event.properties.value)",
      updated_at: "2026-01-06T11:30:00Z",
      deleted_at: nil
    }
  end

  it "renders the scalar fields of V1 and updated_at, without filters nor counters" do
    expect(payload).to eq(scalar_payload)
  end

  # V1 adds its counters with this option, and its filters always.
  context "with V1's counters option" do
    let(:includes) { %i[counters] }

    it "renders the same payload as without options" do
      expect(payload).to eq(scalar_payload)
    end
  end

  context "when the metric is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-09-30T12:00:00Z") }

    it "renders its deletion date" do
      expect(payload).to eq(scalar_payload.merge(deleted_at: "2026-09-30T12:00:00Z"))
    end
  end
end
