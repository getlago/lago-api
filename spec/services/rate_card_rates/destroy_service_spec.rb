# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRates::DestroyService, :capture_kafka_messages do
  subject(:result) { described_class.call(rate_card_rate:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:rate_card) { create(:rate_card, organization:) }

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  context "with a pending rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
    end

    it "soft deletes the rate" do
      expect(result).to be_success
      expect(rate_card_rate.reload).to be_discarded
    end

    it "publishes rate_card_rate.deleted on the discarded rate without a snapshot" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("rate_card_rate.deleted", rate_card_rate)
      expect(Utils::ActivityLog).to have_received(:produce).with(
        rate_card_rate,
        "rate_card_rate.deleted",
        after_commit: true
      )
      expect(rate_card.rates).not_to include(rate_card_rate)
      expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "rate_card.updated", any_args)
    end

    context "when the catalog flag is disabled" do
      let(:organization) { create(:organization) }

      it "still schedules the pair for an unguarded direct service call" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("rate_card_rate.deleted", rate_card_rate)
        expect(result).to be_success
        expect(Utils::ActivityLog).to have_received(:produce).with(
          rate_card_rate,
          "rate_card_rate.deleted",
          after_commit: true
        )
        expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "rate_card.updated", any_args)
      end
    end

    context "when the surrounding transaction rolls back" do
      it "rolls back the deletion and suppresses both event channels" do
        rate_card_rate
        allow(Utils::ActivityLog).to receive(:available?).and_return(true)

        expect do
          ActiveRecord::Base.transaction(requires_new: true) do
            result
            raise ActiveRecord::Rollback
          end
        end.not_to have_enqueued_job(SendWebhookJob)

        expect(rate_card_rate.reload).not_to be_discarded
        expect(kafka_messages).to be_empty
      end
    end
  end

  context "with an active rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day)
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:status]).to eq(["only_pending_rates_can_be_deleted"])
    end

    it "does not publish catalog events" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
    end
  end

  context "when rate_card_rate is nil" do
    let(:rate_card_rate) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card_rate")
    end
  end

  context "when the card is attached to a subscription" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
    end

    before { create(:contract_rate_card, organization:, rate_card:) }

    it "deletes the pending rate" do
      expect(result).to be_success
      expect(rate_card_rate.reload).to be_discarded
    end
  end
end
