# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::DestroyService do
  subject(:result) { described_class.call(rate_phase:) }

  let_it_be(:organization) { create(:organization) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }
  let!(:launch) { create(:rate_phase, plan_rate_card:, organization:, position: 1, billing_interval_cycle_count: 3) }
  let!(:ramp) { create(:rate_phase, plan_rate_card:, organization:, position: 2, billing_interval_cycle_count: 6) }
  let!(:terminal) { create(:rate_phase, plan_rate_card:, organization:, position: 3, billing_interval_cycle_count: nil) }

  before {
    allow(Utils::ActivityLog).to receive(:produce_after_commit).and_yield
    create_default(:plan)
    create_default(:billable_metric)
  }

  def activity_payload(owner, event_type)
    expect(kafka_messages.size).to eq(1)
    payload = JSON.parse(kafka_messages.first.fetch(:payload))
    expect(payload).to include(
      "activity_type" => event_type,
      "resource_id" => owner.id,
      "resource_type" => owner.class.name
    )
    payload
  end

  context "when deleting a middle phase" do
    let(:rate_phase) { ramp }

    it "discards it and shifts the later phases up" do
      expect(result).to be_success
      expect(ramp.reload).to be_discarded
      expect(launch.reload.position).to eq(1)
      expect(terminal.reload.position).to eq(2)
    end

    it "publishes one owning plan_rate_card.updated pair with the post-delete hierarchy" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan_rate_card.updated", plan_rate_card)

      expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(
        plan_rate_card,
        "plan_rate_card.updated"
      )
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

    it "returns a validation failure and leaves the sequence untouched" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phase]).to eq(["indefinite_phase_not_deletable"])
      expect(terminal.reload).not_to be_discarded
      expect(ramp.reload.billing_interval_cycle_count).to eq(6)
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "plan_rate_card.updated", any_args)
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

  context "when the plan has contracts" do
    let(:rate_phase) { ramp }

    before { create(:contract, catalog_plan: plan_rate_card.catalog_plan, organization: plan_rate_card.organization) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phase]).to eq(["plan_locked"])
    end
  end

  context "when the phase was deleted concurrently" do
    let(:rate_phase) { ramp }

    before { ramp.discard! }

    it "returns a not found failure without touching the sequence" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(terminal.reload.position).to eq(3)
    end
  end

  context "when rate_phase is nil" do
    let(:rate_phase) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the phase belongs to a contract rate card" do
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, :pending, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
    let(:rate_phase) do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 1, billing_interval_cycle_count: 3)
    end
    let!(:contract_terminal) do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 2, billing_interval_cycle_count: nil)
    end

    it "publishes one contract_rate_card.updated pair" do
      rate_phase
      contract_terminal
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract_rate_card.updated", contract_rate_card)

      expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(
        contract_rate_card,
        "contract_rate_card.updated"
      )
    end
  end

  context "when logging phase removal", :capture_kafka_messages, transaction: false do
    let(:organization) { create(:organization) }
    let!(:launch) { create(:rate_phase, plan_rate_card:, organization:, code: "launch", position: 1, billing_interval_cycle_count: 3) }
    let!(:ramp) { create(:rate_phase, plan_rate_card:, organization:, code: "ramp", position: 2, billing_interval_cycle_count: 6) }
    let!(:terminal) { create(:rate_phase, plan_rate_card:, organization:, code: "forever", position: 3, billing_interval_cycle_count: nil) }
    let(:rate_phase) { ramp }

    before do
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
      allow(Utils::ActivityLog).to receive(:produce_after_commit).and_call_original
    end

    it "emits one owner update with ordered phases and the count delta" do
      expect(result).to be_success
      payload = activity_payload(plan_rate_card, "plan_rate_card.updated")
      before_phases, after_phases = payload.fetch("activity_object_changes").fetch("rate_phases")
      expect([before_phases.map { |phase| phase.fetch("code") }, after_phases.map { |phase| phase.fetch("code") }])
        .to eq([%w[launch ramp forever], %w[launch forever]])
      expect(payload.fetch("activity_object_changes").fetch("rate_phases_count")).to eq([3, 2])
    end
  end
end
