# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::PlanRateCardSerializer do
  subject(:payload) { described_class.new(plan_rate_card).serialize }

  let(:plan_rate_card) { create(:plan_rate_card, units:, deleted_at:) }
  let(:units) { nil }
  let(:deleted_at) { nil }
  let(:flat_payload) do
    {
      lago_id: plan_rate_card.id,
      plan_code: plan_rate_card.catalog_plan.code,
      rate_card_code: plan_rate_card.rate_card.code,
      units: nil,
      rate_phases_count: 0,
      created_at: plan_rate_card.created_at.iso8601,
      updated_at: plan_rate_card.updated_at.iso8601,
      deleted_at: nil
    }
  end

  it "serializes the applied rate card, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
  end

  context "with units and rate phases" do
    # Too precise for a Float, so rendering units as a Float fails the comparison.
    let(:units) { BigDecimal("12.3456789012345678901") }

    before do
      create(:rate_phase, organization: plan_rate_card.organization, plan_rate_card:, position: 1)
      create(:rate_phase, organization: plan_rate_card.organization, plan_rate_card:, position: 2)
      create(:rate_phase, organization: plan_rate_card.organization, plan_rate_card:, position: 3, deleted_at: Time.current)
    end

    it "renders the units and counts the kept rate phases only" do
      expect(payload).to eq(flat_payload.merge(units: BigDecimal("12.3456789012345678901"), rate_phases_count: 2))
    end
  end

  context "when the applied rate card is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-10-01 10:00:00") }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-10-01T10:00:00Z"))
    end
  end
end
