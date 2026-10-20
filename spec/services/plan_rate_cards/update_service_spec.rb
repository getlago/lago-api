# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCards::UpdateService do
  subject(:result) { described_class.call(plan_rate_card:, params:) }

  let_it_be(:organization) { create(:organization) }

  before_all do
    create_default(:billable_metric)
  end

  let_it_be(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, units: 5) }

  let(:params) { {units: "12"} }

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  it "updates the entry" do
    expect(result).to be_success
    expect(result.plan_rate_card.units).to eq(12)
  end

  context "when another instance has already destroyed the entry" do
    subject(:result) { described_class.call(plan_rate_card: stale_plan_rate_card, params:) }

    let(:stale_plan_rate_card) { PlanRateCard.find(plan_rate_card.id) }

    before do
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
      stale_plan_rate_card
      PlanRateCards::DestroyService.call(plan_rate_card:)
    end

    it "returns not found without changing units or publishing an update", :capture_kafka_messages do
      expect do
        expect(result).not_to be_success
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(result.error.resource).to eq("applied_rate_card")
      expect(plan_rate_card.reload.units).to eq(5)
      expect(kafka_messages.map { |message| JSON.parse(message.fetch(:payload)).fetch("activity_type") }).not_to include("plan_rate_card.updated")
    end
  end

  it "publishes plan_rate_card.updated with the post-write hierarchy" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan_rate_card.updated", plan_rate_card)

    expect(Utils::ActivityLog).to have_received(:produce).with(
      plan_rate_card,
      "plan_rate_card.updated",
      after_commit: true
    )
  end

  context "when the submitted units are unchanged" do
    let(:params) { {units: "5"} }

    it "publishes the update even when its serialized state is unchanged" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan_rate_card.updated", plan_rate_card)
      expect(Utils::ActivityLog).to have_received(:produce).with(plan_rate_card, "plan_rate_card.updated", after_commit: true)
    end
  end

  context "when the plan has contracts" do
    before do
      create(:contract, catalog_plan:, organization:)
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "forbids the update without delivering either event", :capture_kafka_messages do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
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
