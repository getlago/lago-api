# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::DestroyService do
  subject(:result) { described_class.call(rate_phase:) }

  let_it_be(:organization) { create(:organization) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }
  let!(:launch) { create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3) }
  let!(:ramp) { create(:rate_phase, plan_rate_card:, organization:, position: 2, billing_interval_cycle_count: 6) }
  let!(:terminal) { create(:rate_phase, plan_rate_card:, organization:, position: 3, billing_interval_cycle_count: nil) }

  before_all do
    create_default(:plan)
    create_default(:billable_metric)
  end

  context "when deleting a middle phase" do
    let(:rate_phase) { ramp }

    it "discards it and shifts the later phases up" do
      expect(result).to be_success
      expect(ramp.reload).to be_discarded
      expect(launch.reload.position).to eq(1)
      expect(terminal.reload.position).to eq(2)
    end

    it "discards the phase's override with it" do
      override = create(:rate_override, organization:)
      ramp.update!(rate_override_id: override.id)

      expect(result).to be_success
      expect(override.reload).to be_discarded
    end

    it "locks the parent entry while renumbering" do
      parent = ramp.plan_rate_card
      allow(ramp).to receive(:plan_rate_card).and_return(parent)
      allow(parent).to receive(:with_lock).and_call_original

      expect(result).to be_success
      expect(parent).to have_received(:with_lock)
    end
  end

  context "when deleting the indefinite terminal phase" do
    let(:rate_phase) { terminal }

    it "auto-promotes the new last phase to indefinite" do
      expect(result).to be_success
      expect(terminal.reload).to be_discarded
      expect(ramp.reload.billing_interval_cycle_count).to be_nil
    end
  end

  context "when deleting a definite terminal phase" do
    let(:rate_phase) { ramp }

    before { terminal.discard! && ramp.update!(billing_interval_cycle_count: 6) }

    it "does not touch the new last phase" do
      expect(result).to be_success
      expect(launch.reload.billing_interval_cycle_count).to eq(3)
    end
  end

  context "when deleting the only phase" do
    let(:rate_phase) { launch }

    before do
      ramp.discard!
      terminal.discard!
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phase]).to eq(["cannot_delete_last_phase"])
    end
  end

  context "when the plan has subscriptions" do
    let(:rate_phase) { ramp }

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
