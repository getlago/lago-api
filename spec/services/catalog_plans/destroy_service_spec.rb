# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(catalog_plan:) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:) }
  let(:rate_override) { create(:rate_override, organization:) }
  let(:phase) { create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override:) }

  before { allow(Utils::ActivityLog).to receive(:produce) }

  it "soft deletes the catalog plan" do
    expect(result).to be_success
    expect(result.catalog_plan).to be_discarded
    expect(organization.catalog_plans.kept).to be_empty
  end

  it "tears down the plan's rate cards, phases and overrides" do
    phase

    result

    expect(plan_rate_card.reload).to be_discarded
    expect(phase.reload).to be_discarded
    expect(rate_override.reload).to be_discarded
  end

  it "publishes the shared plan.deleted event and legacy activity arguments" do
    phase

    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.deleted", catalog_plan)
    expect(Utils::ActivityLog).to have_received(:produce).with(catalog_plan, "plan.deleted", after_commit: true)
    expect(SendWebhookJob).not_to have_been_enqueued.with("plan_rate_card.deleted", anything, anything)
    expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "plan_rate_card.deleted", any_args)
    expect(catalog_plan.reload).to be_discarded
  end

  it "delivers legacy webhook and activity payloads after the plan is discarded", transaction: false do
    create(:webhook_endpoint, organization:)
    phase
    allow(Utils::ActivityLog).to receive(:produce).and_call_original
    allow(Utils::ActivityLog).to receive(:available?).and_return(true)

    perform_enqueued_jobs(only: SendWebhookJob) { result }

    webhook = Webhook.find_by!(webhook_type: "plan.deleted")
    expect(webhook.payload.fetch("plan").fetch("applied_rate_cards_count")).to eq(0)
    expect(webhook.payload.fetch("plan")).not_to have_key("applied_rate_cards")
    activity = JSON.parse(kafka_messages.find { |message| JSON.parse(message[:payload]).fetch("activity_type") == "plan.deleted" }.fetch(:payload))
    expect(activity.fetch("activity_object")).not_to have_key("applied_rate_cards")
    expect(Webhook.where(webhook_type: "plan_rate_card.deleted")).not_to exist
  end

  context "when the plan is attached to contracts" do
    before { create(:contract, organization:, catalog_plan:) }

    it "blocks the deletion" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
      expect(catalog_plan.reload).not_to be_discarded
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when the surrounding transaction rolls back" do
    before do
      allow(Utils::ActivityLog).to receive(:produce).and_call_original
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "does not deliver either event channel", transaction: false do
      plan_rate_card

      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(kafka_messages).to be_empty
      expect(catalog_plan.reload).not_to be_discarded
      expect(plan_rate_card.reload).not_to be_discarded
    end
  end

  context "when the catalog plan is missing" do
    let(:catalog_plan) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
