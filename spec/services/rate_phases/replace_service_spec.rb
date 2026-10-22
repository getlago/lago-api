# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhases::ReplaceService, :capture_kafka_messages do
  subject(:result) { described_class.call(plan_rate_card:, phases_params:) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:phases_params) do
    [
      {code: "trial", position: 1, name: "trial", billing_interval_cycle_count: 3},
      {code: "standard", position: 2, name: "standard", billing_interval_cycle_count: nil}
    ]
  end
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:) }

  before {
    create_default(:billable_metric)
    allow(Utils::ActivityLog).to receive(:produce_after_commit).and_yield
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

  it "replaces the phase sequence and discards the superseded overrides" do
    previous_override = create(:rate_override, organization:)
    create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override_id: previous_override.id)

    expect { result }.to change { plan_rate_card.rate_phases.reload.order(:position).pluck(:name) }
      .to(%w[trial standard])

    expect(previous_override.reload).to be_discarded

    expect(result).to be_success
    expect(result.rate_phases.map(&:position)).to eq([1, 2])
    expect(result.rate_phases.map(&:billing_interval_cycle_count)).to eq([3, nil])
  end

  it "publishes one owning plan_rate_card.updated pair for the replacement" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan_rate_card.updated", plan_rate_card)

    expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(
      plan_rate_card,
      "plan_rate_card.updated"
    )
  end

  it "suppresses the owner pair when invoked as part of a larger write" do
    expect do
      described_class.call(plan_rate_card:, phases_params:, emit_events: false)
    end.not_to have_enqueued_job(SendWebhookJob)
    expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "plan_rate_card.updated", any_args)
  end

  context "when an outer transaction rolls back" do
    before do
      allow(Utils::ActivityLog).to receive(:produce_after_commit).and_call_original
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "does not deliver either owner event", transaction: false do
      plan_rate_card
      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(kafka_messages).to be_empty
    end
  end

  it "locks the entry while replacing the sequence" do
    allow(plan_rate_card).to receive(:with_lock).and_call_original

    result

    expect(plan_rate_card).to have_received(:with_lock)
  end

  it "accepts positions provided out of order" do
    result = described_class.call(
      plan_rate_card:,
      phases_params: [
        {code: "standard", position: 2, billing_interval_cycle_count: nil},
        {code: "trial", position: 1, billing_interval_cycle_count: 3}
      ]
    )

    expect(result).to be_success
    expect(result.rate_phases.map(&:position)).to eq([1, 2])
  end

  context "with a rate override on a phase" do
    let(:phases_params) do
      [
        {
          code: "trial",
          position: 1,
          name: "trial",
          billing_interval_cycle_count: 3,
          rate_override: {rate_model: "standard", rate_properties: {"amount" => "0"}, min_amount_cents: 0}
        },
        {code: "standard", position: 2, billing_interval_cycle_count: nil}
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
        existing_count = RatePhase.count
        expect { result }.not_to have_enqueued_job(SendWebhookJob)
        expect(RatePhase.count).to eq(existing_count)
        expect(result).not_to be_success
        expect(result.error.messages[:pricing_unit_conversion_rate]).to include("value_is_mandatory")
        expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "plan_rate_card.updated", any_args)
      end
    end
  end

  context "when the plan product is missing" do
    let(:plan_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("applied_rate_card")
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
      expect(result.error.messages[:rate_phases]).to include("positions_must_be_contiguous")
    end
  end

  context "when a position is not an integer" do
    let(:phases_params) do
      [
        {position: "1abc", billing_interval_cycle_count: 3},
        {position: 2, billing_interval_cycle_count: nil}
      ]
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to include("positions_must_be_contiguous")
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
      expect(result.error.messages[:rate_phases]).to include("indefinite_phase_must_be_last")
    end
  end

  context "when the last phase is definite" do
    let(:phases_params) do
      [
        {position: 1, billing_interval_cycle_count: 2},
        {position: 2, billing_interval_cycle_count: 3}
      ]
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to eq(["last_phase_must_be_indefinite"])
    end
  end

  context "when the plan is attached to a contract" do
    before { create(:contract, catalog_plan:, organization:) }

    it "returns a plan_locked failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to include("plan_locked")
    end
  end

  context "when logging phase replacement", transaction: false do
    let!(:previous_intro) do
      create(:rate_phase, organization:, plan_rate_card:, code: "intro", name: "Intro", position: 1, billing_interval_cycle_count: 3)
    end
    let!(:previous_terminal) do
      create(:rate_phase, organization:, plan_rate_card:, code: "forever", name: "Forever", position: 2, billing_interval_cycle_count: nil)
    end
    let(:phases_params) do
      [
        {code: "new-intro", name: "New intro", position: 1, billing_interval_cycle_count: 2},
        {code: "new-middle", name: "New middle", position: 2, billing_interval_cycle_count: 4},
        {code: "new-forever", name: "New forever", position: 3, billing_interval_cycle_count: nil}
      ]
    end

    before do
      previous_intro
      previous_terminal
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
      allow(Utils::ActivityLog).to receive(:produce_after_commit).and_call_original
    end

    it "emits one owner update with complete ordered before/after phases and count change" do
      expect(result).to be_success
      payload = activity_payload(plan_rate_card, "plan_rate_card.updated")
      before_phases, after_phases = payload.fetch("activity_object_changes").fetch("rate_phases")
      expect([before_phases.map { |phase| phase.fetch("code") }, after_phases.map { |phase| phase.fetch("code") }])
        .to eq([%w[intro forever], %w[new-intro new-middle new-forever]])
      expect(payload.fetch("activity_object_changes").fetch("rate_phases_count")).to eq([2, 3])
      expect(after_phases.map { |phase| phase.fetch("lago_id") } & before_phases.map { |phase| phase.fetch("lago_id") }).to be_empty
    end
  end
end
