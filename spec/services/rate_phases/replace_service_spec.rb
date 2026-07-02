# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::ReplaceService do
  subject(:result) { described_class.call(plan_product_item:, phases_params:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_product_item) { create(:plan_product_item, organization:, plan:, rate_card:) }

  let(:phases_params) do
    [
      {position: 1, name: "trial", billing_interval_cycle_count: 3},
      {position: 2, name: "standard", billing_interval_cycle_count: nil}
    ]
  end

  it "replaces the phase sequence" do
    create(:rate_phase, organization:, plan_product_item:, position: 1)

    expect { result }.to change { plan_product_item.rate_phases.reload.pluck(:name) }
      .to(%w[trial standard])

    expect(result).to be_success
    expect(result.rate_phases.map(&:position)).to eq([1, 2])
    expect(result.rate_phases.map(&:billing_interval_cycle_count)).to eq([3, nil])
  end

  it "accepts positions provided out of order" do
    result = described_class.call(
      plan_product_item:,
      phases_params: [
        {position: 2, billing_interval_cycle_count: nil},
        {position: 1, billing_interval_cycle_count: 3}
      ]
    )

    expect(result).to be_success
    expect(result.rate_phases.map(&:position)).to eq([1, 2])
  end

  context "when the plan product item is missing" do
    let(:plan_product_item) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("plan_product_item")
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
