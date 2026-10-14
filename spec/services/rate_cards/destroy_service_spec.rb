# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCards::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(rate_card:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:rate_card) { create(:rate_card, organization:) }

  before do
    allow(Utils::ActivityLog).to receive(:produce).and_call_original
    create(:rate_card_rate, organization:, rate_card:) if rate_card
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
