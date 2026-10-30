# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCards::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(rate_card:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:active_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.current.beginning_of_day) }

  before do
    create_default(:billable_metric)
    allow(Utils::ActivityLog).to receive(:produce).and_call_original
    active_rate if rate_card
  end

  it "soft deletes the card and its rates" do
    rate_ids = rate_card.rates.ids

    expect(result).to be_success
    expect(rate_card.reload).to be_discarded
    expect(RateCardRate.with_discarded.where(id: rate_ids).map(&:discarded?)).to all(be(true))
  end

  it "publishes rate_card.deleted on the discarded card without a snapshot" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("rate_card.deleted", rate_card)
    expect(Utils::ActivityLog).to have_received(:produce).with(
      rate_card,
      "rate_card.deleted",
      after_commit: true
    )
    expect(rate_card.reload.rates).to be_empty
    expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "rate_card_rate.deleted", any_args)
  end

  context "when delivering deletion events", transaction: false do
    let(:tax) { create(:tax, organization:) }
    let(:webhook_endpoint) { create(:webhook_endpoint, organization:) }

    before do
      webhook_endpoint
      create(:rate_card_applied_tax, rate_card:, tax:, organization:)
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "omits rate and tax snapshots from the deleted webhook while retaining them in activity" do
      perform_enqueued_jobs(only: SendWebhookJob) { result }

      webhook_payload = Webhook.find_by!(webhook_type: "rate_card.deleted").payload.fetch("rate_card")
      expect(webhook_payload).not_to have_key("rates_count")
      expect(webhook_payload).not_to have_key("active_rate")
      expect(webhook_payload).not_to have_key("rates")
      expect(webhook_payload).not_to have_key("taxes")
      expect(kafka_messages.size).to eq(1)

      activity_payload = JSON.parse(kafka_messages.first.fetch(:payload)).fetch("activity_object")
      expect(activity_payload).not_to have_key("active_rate")
      expect(activity_payload).to include("rates" => [])
      expect(activity_payload.fetch("taxes").map { |item| item.fetch("lago_id") }).to eq([tax.id])
    end

    context "when rate associations are preloaded before deletion" do
      before { rate_card.rates.load }

      it "omits rate and tax snapshots from the deleted webhook while retaining activity details" do
        perform_enqueued_jobs(only: SendWebhookJob) { result }

        webhook_payload = Webhook.find_by!(webhook_type: "rate_card.deleted").payload.fetch("rate_card")
        expect(webhook_payload).not_to have_key("rates_count")
        expect(webhook_payload).not_to have_key("active_rate")
        expect(webhook_payload).not_to have_key("rates")
        expect(webhook_payload).not_to have_key("taxes")

        activity_payload = JSON.parse(kafka_messages.first.fetch(:payload)).fetch("activity_object")
        expect(activity_payload).not_to have_key("active_rate")
        expect(activity_payload).not_to have_key("rates_count")
        expect(activity_payload).to include("rates" => [])
        expect(activity_payload.fetch("taxes").map { |item| item.fetch("lago_id") }).to eq([tax.id])
      end
    end
  end

  context "when the catalog flag is disabled" do
    let(:organization) { create(:organization) }

    it "still schedules the pair for an unguarded direct service call" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("rate_card.deleted", rate_card)
      expect(result).to be_success
      expect(Utils::ActivityLog).to have_received(:produce).with(
        rate_card,
        "rate_card.deleted",
        after_commit: true
      )
    end
  end

  context "when the surrounding transaction rolls back" do
    before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

    it "rolls back the deletion and suppresses both event channels" do
      expect do
        ActiveRecord::Base.transaction do
          result
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job(SendWebhookJob)

      expect(rate_card.reload).not_to be_discarded
      expect(kafka_messages).to be_empty
    end
  end

  context "when rate_card is nil" do
    let(:rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end

  context "when the card is attached to a plan" do
    before { create(:plan_rate_card, organization:, rate_card:) }

    it "returns a validation failure and discards nothing" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_card]).to eq(["attached_to_plan_or_subscription"])
      expect(rate_card.reload).not_to be_discarded
    end
  end
end
