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

  it "locks the parent entry like the other sequence mutations" do
    allow(rate_phase).to receive(:plan_rate_card).and_return(plan_rate_card)
    allow(plan_rate_card).to receive(:with_lock).and_call_original

    result

    expect(plan_rate_card).to have_received(:with_lock)
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

    context "when the cycle count is an empty string" do
      let(:params) { {billing_interval_cycle_count: ""} }

      it "treats it as indefinite and rejects it too" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_interval_cycle_count]).to eq(["indefinite_phase_must_be_last"])
      end
    end
  end

  describe "rate override lifecycle" do
    let(:params) { {rate_override: {rate_model: "standard", rate_properties: {"amount" => "2"}}} }

    let!(:previous_override) { create(:rate_override, organization:) }

    before { rate_phase.update!(rate_override_id: previous_override.id) }

    it "replaces the override and discards the superseded one" do
      expect(result).to be_success
      expect(rate_phase.reload.rate_override.rate_properties).to eq({"amount" => "2"})
      expect(previous_override.reload).to be_discarded
    end

    context "when the override is null" do
      let(:params) { {rate_override: nil} }

      it "clears the override and discards it" do
        expect(result).to be_success
        expect(rate_phase.reload.rate_override).to be_nil
        expect(previous_override.reload).to be_discarded
      end
    end

    context "when the override is an empty object" do
      let(:params) { {rate_override: {}} }

      it "fails validation instead of clearing the override" do
        expect(result).not_to be_success
        expect(result.error.messages).to have_key(:rate_model)
        expect(rate_phase.reload.rate_override).to eq(previous_override)
        expect(previous_override.reload).not_to be_discarded
      end
    end

    context "when the phase save fails" do
      before { create(:rate_phase, plan_rate_card:, organization:, position: 2, code: "taken") }

      let(:params) { {code: "taken", rate_override: {rate_model: "standard", rate_properties: {"amount" => "2"}}} }

      it "rolls everything back without leaking an override" do
        expect { result }.not_to change(RateOverride, :count)

        expect(result).not_to be_success
        expect(previous_override.reload).not_to be_discarded
        expect(rate_phase.reload.rate_override).to eq(previous_override)
      end
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
