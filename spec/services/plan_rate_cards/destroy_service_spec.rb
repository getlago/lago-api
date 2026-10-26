# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCards::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(plan_rate_card:) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:) }

  before do
    create_default(:billable_metric)
  end

  it "soft deletes the entry" do
    expect(result).to be_success
    expect(result.plan_rate_card).to be_discarded
    expect(catalog_plan.reload.applied_rate_cards).to be_empty
  end

  context "when another instance has already destroyed the entry" do
    subject(:result) { described_class.call(plan_rate_card: stale_plan_rate_card) }

    let(:stale_plan_rate_card) { PlanRateCard.find(plan_rate_card.id) }

    before do
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
      stale_plan_rate_card
      described_class.call(plan_rate_card:)
    end

    it "returns not found without publishing another event pair", :capture_kafka_messages do
      expect do
        expect(result).not_to be_success
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(result.error.resource).to eq("applied_rate_card")
      expect(kafka_messages.count { |message| JSON.parse(message.fetch(:payload)).fetch("activity_type") == "plan_rate_card.deleted" }).to eq(1)
    end
  end

  it "discards the entry's phases and their overrides" do
    rate_override = create(:rate_override, organization:)
    phase = create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override:)

    result

    expect(phase.reload).to be_discarded
    expect(rate_override.reload).to be_discarded
  end

  it "publishes one legacy plan_rate_card.deleted pair without a snapshot" do
    override = create(:rate_override, organization:)
    phase = create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override: override)
    allow(Utils::ActivityLog).to receive(:available?).and_return(true)

    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with(
      "plan_rate_card.deleted",
      plan_rate_card
    )
    activity = JSON.parse(kafka_messages.sole.fetch(:payload))
    expect(activity).to include(
      "activity_type" => "plan_rate_card.deleted",
      "resource_type" => "PlanRateCard",
      "resource_id" => plan_rate_card.id
    )
    expect(activity.fetch("activity_object")).to include("lago_id" => plan_rate_card.id)
    expect(activity.fetch("activity_object")).not_to have_key("rate_phases_count")
    expect(activity.fetch("activity_object")).not_to have_key("rate_phases")
    expect(phase.reload).to be_discarded
    expect(override.reload).to be_discarded
    expect(plan_rate_card.reload.rate_phases).to be_empty
    serialized_card = ::V2::PlanRateCardSerializer.new(plan_rate_card, root_name: "plan_rate_card").serialize
    expect(serialized_card).not_to have_key(:rate_phases_count)
    expect(serialized_card).not_to have_key(:rate_phases)
  end

  it "supports suppressing the card event pair for a caller-owned cascade" do
    override = create(:rate_override, organization:)
    phase = create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override: override)
    allow(Utils::ActivityLog).to receive(:available?).and_return(true)

    expect do
      described_class.call(plan_rate_card:, emit_events: false)
    end.not_to have_enqueued_job(SendWebhookJob)
    expect(kafka_messages).to be_empty
    expect(phase.reload).to be_discarded
    expect(override.reload).to be_discarded
  end

  context "when the surrounding transaction rolls back" do
    before do
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "does not deliver the deletion pair", transaction: false do
      plan_rate_card
      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(kafka_messages).to be_empty
      expect(plan_rate_card.reload).not_to be_discarded
    end
  end

  context "when the plan has contracts" do
    before { create(:contract, catalog_plan:, organization:) }

    it "forbids the deletion" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
      expect(plan_rate_card.reload).not_to be_discarded
      expect(kafka_messages).to be_empty
    end
  end

  context "when the entry is missing" do
    let(:plan_rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("applied_rate_card")
    end
  end
end
