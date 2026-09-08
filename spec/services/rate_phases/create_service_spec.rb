# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::CreateService do
  subject(:result) { described_class.call(plan_rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }

  let(:params) { {code: "trial", position: 1, billing_interval_cycle_count: 6, name: "Trial period"} }

  it "creates a rate phase" do
    expect { result }.to change(RatePhase, :count).by(1)

    rate_phase = result.rate_phase
    expect(rate_phase.plan_rate_card).to eq(plan_rate_card)
    expect(rate_phase.organization).to eq(organization)
    expect(rate_phase.position).to eq(1)
    expect(rate_phase.billing_interval_cycle_count).to eq(6)
    expect(rate_phase.name).to eq("Trial period")
    expect(rate_phase.code).to eq("trial")
  end

  it "locks the parent entry while renumbering" do
    allow(plan_rate_card).to receive(:with_lock).and_call_original

    result

    expect(plan_rate_card).to have_received(:with_lock)
  end

  context "when the code is missing" do
    before { params.delete(:code) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end

  context "when inserting between existing phases" do
    let!(:launch) { create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3) }
    let!(:standard) { create(:rate_phase, plan_rate_card:, organization:, position: 2, billing_interval_cycle_count: nil) }

    let(:params) { {code: "ramp", position: 2, billing_interval_cycle_count: 6, name: "Ramp"} }

    it "shifts the later phases down" do
      expect(result).to be_success
      expect(result.rate_phase.position).to eq(2)
      expect(launch.reload.position).to eq(1)
      expect(standard.reload.position).to eq(3)
    end
  end

  context "when position is omitted" do
    let!(:terminal) { create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: nil) }

    let(:params) { {code: "intro", billing_interval_cycle_count: 3} }

    it "inserts a definite phase before the indefinite tail" do
      expect(result).to be_success
      expect(result.rate_phase.position).to eq(1)
      expect(terminal.reload.position).to eq(2)
    end

    context "when the new phase is indefinite" do
      let(:params) { {billing_interval_cycle_count: nil} }

      it "rejects a second indefinite phase" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_interval_cycle_count]).to eq(["indefinite_phase_must_be_last"])
      end
    end
  end

  context "when the position is out of range" do
    let(:params) { {position: 3, billing_interval_cycle_count: 3} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:position]).to eq(["positions_must_be_contiguous"])
    end
  end

  context "when inserting an indefinite phase before the end" do
    before { create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3) }

    let(:params) { {position: 1, billing_interval_cycle_count: nil} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_interval_cycle_count]).to eq(["indefinite_phase_must_be_last"])
    end

    context "when the cycle count is an empty string" do
      let(:params) { {code: "sneaky", position: 1, billing_interval_cycle_count: ""} }

      it "treats it as indefinite and rejects it too" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_interval_cycle_count]).to eq(["indefinite_phase_must_be_last"])
      end
    end
  end

  context "when the plan has subscriptions" do
    before { create(:subscription, plan: plan_rate_card.plan, organization:) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phase]).to eq(["plan_locked"])
    end
  end

  context "when no parent is provided" do
    subject(:result) { described_class.call(params:) }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
