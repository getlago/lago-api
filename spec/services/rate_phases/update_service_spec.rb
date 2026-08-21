# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::UpdateService do
  subject(:result) { described_class.call(rate_phase:, params:) }

  let(:organization) { create(:organization) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }
  let(:rate_phase) { create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3, name: "Before") }

  let(:params) { {name: "After", billing_interval_cycle_count: 6} }

  it "updates the phase" do
    expect(result).to be_success
    expect(rate_phase.reload.name).to eq("After")
    expect(rate_phase.billing_interval_cycle_count).to eq(6)
  end

  context "when renaming the code" do
    let(:params) { {code: "launch"} }

    it "updates it" do
      expect(result).to be_success
      expect(rate_phase.reload.code).to eq("launch")
    end
  end

  context "when making a non-terminal phase indefinite" do
    before { create(:rate_phase, plan_rate_card:, organization:, position: 2, billing_interval_cycle_count: nil) }

    let(:params) { {billing_interval_cycle_count: nil} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_interval_cycle_count]).to eq(["indefinite_phase_must_be_last"])
    end
  end

  context "when making the last phase indefinite" do
    let(:params) { {billing_interval_cycle_count: nil} }

    it "succeeds" do
      expect(result).to be_success
      expect(rate_phase.reload.billing_interval_cycle_count).to be_nil
    end
  end

  context "when the plan has subscriptions" do
    before { create(:subscription, plan: plan_rate_card.plan, organization:) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phase]).to eq(["plan_locked"])
    end
  end

  context "when rate_phase is nil" do
    let(:rate_phase) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
