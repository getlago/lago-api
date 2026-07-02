# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::ReplaceService do
  subject(:result) { described_class.call(plan_rate_card:, phases_params:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }

  let(:phases_params) do
    [
      {position: 1, name: "trial", billing_interval_cycle_count: 3},
      {position: 2, name: "standard", billing_interval_cycle_count: nil}
    ]
  end

  it "replaces the phase sequence" do
    create(:rate_phase, organization:, plan_rate_card:, position: 1)

    expect { result }.to change { plan_rate_card.rate_phases.reload.pluck(:name) }
      .to(%w[trial standard])

    expect(result).to be_success
    expect(result.rate_phases.map(&:position)).to eq([1, 2])
    expect(result.rate_phases.map(&:billing_interval_cycle_count)).to eq([3, nil])
  end

  it "accepts positions provided out of order" do
    result = described_class.call(
      plan_rate_card:,
      phases_params: [
        {position: 2, billing_interval_cycle_count: nil},
        {position: 1, billing_interval_cycle_count: 3}
      ]
    )

    expect(result).to be_success
    expect(result.rate_phases.map(&:position)).to eq([1, 2])
  end

  context "with a rate override on a phase" do
    let(:phases_params) do
      [
        {
          position: 1,
          name: "trial",
          billing_interval_cycle_count: 3,
          rate_override: {rate_model: "standard", rate_properties: {"amount" => "0"}, min_amount_cents: 0}
        },
        {position: 2, billing_interval_cycle_count: nil}
      ]
    end

    it "creates the override and links it to the phase" do
      expect { result }.to change(RateOverride, :count).by(1)

      first_phase = result.rate_phases.first
      expect(first_phase.rate_override).to be_present
      expect(first_phase.rate_override.rate_properties).to eq({"amount" => "0"})
      expect(result.rate_phases.last.rate_override).to be_nil
    end

    it "discards the previous phase's override when replacing" do
      previous_override = create(:rate_override, organization:)
      create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override_id: previous_override.id)

      result

      expect(previous_override.reload.discarded?).to be(true)
    end

    context "when the override is invalid" do
      let(:rate_card) { create(:rate_card, organization:, applied_pricing_unit_code: "credits") }

      it "propagates the override validation failure and rolls back" do
        expect { result }.not_to change(RatePhase, :count)
        expect(result).not_to be_success
        expect(result.error.messages[:pricing_unit_conversion_rate]).to include("value_is_mandatory")
      end
    end
  end

  context "when the plan product item is missing" do
    let(:plan_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("plan_rate_card")
    end
  end

  context "when no phase is provided" do
    let(:phases_params) { [] }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to include("value_is_mandatory")
    end
  end

  context "when positions are not contiguous" do
    let(:phases_params) do
      [
        {position: 1, billing_interval_cycle_count: 3},
        {position: 3, billing_interval_cycle_count: nil}
      ]
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to include("non_contiguous_position")
    end
  end

  context "when an indefinite phase is not the last one" do
    let(:phases_params) do
      [
        {position: 1, billing_interval_cycle_count: nil},
        {position: 2, billing_interval_cycle_count: 3}
      ]
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to include("non_terminal_indefinite")
    end
  end

  context "when the plan is attached to a subscription" do
    before { create(:subscription, plan:, organization:) }

    it "returns a plan_locked failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to include("plan_locked")
    end
  end
end
