# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRates::UpdateService do
  subject(:result) { described_class.call(rate_card_rate:, params:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:rate_card) { create(:rate_card, organization:) }

  before {
    allow(Utils::ActivityLog).to receive(:produce).and_call_original
    create_default(:billable_metric)
  }

  context "with a pending rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
    end
    let(:params) { {rate_model: "standard", rate_properties: {"amount" => "25"}, billing_interval_count: 3} }

    it "updates all fields" do
      expect(result).to be_success
      expect(result.rate_card_rate.rate_properties).to eq("amount" => "25")
      expect(result.rate_card_rate.billing_interval_count).to eq(3)
    end

    it "publishes rate_card_rate.updated to both channels" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("rate_card_rate.updated", rate_card_rate)

      rate = result.rate_card_rate
      expect(Utils::ActivityLog).to have_received(:produce).with(rate, "rate_card_rate.updated", after_commit: true)
      expect(Utils::ActivityLog).not_to have_received(:produce).with(anything, "rate_card.updated", any_args)
    end

    context "with graduated tiers" do
      let(:params) do
        {
          rate_model: "graduated",
          rate_properties: {graduated_ranges: [{to_value: "10", flat_amount: "0", per_unit_amount: "1"}, {to_value: nil, flat_amount: "0", per_unit_amount: "0.5"}]}
        }
      end

      it "stores each tier starting where the previous one ends" do
        expect(result).to be_success
        expect(result.rate_card_rate.rate_properties["graduated_ranges"].map { it.values_at("from_value", "to_value") })
          .to eq([[0, 10], [10, nil]])
      end

      context "when a tier names its lower bound" do
        let(:params) { {rate_model: "graduated", rate_properties: {graduated_ranges: [{from_value: 0, to_value: nil, flat_amount: "0", per_unit_amount: "1"}]}} }

        it "returns a validation failure and keeps the stored properties" do
          expect(result.error.messages[:graduated_ranges]).to eq(["from_value_not_allowed"])
          expect(rate_card_rate.reload.rate_properties).to eq("amount" => "10")
        end
      end
    end

    context "when the effective_from is moved to the start of today" do
      let(:params) { {effective_from: Time.current.beginning_of_day.iso8601} }

      it "activates the rate" do
        expect(result).to be_success
        expect(result.rate_card_rate.status).to eq("active")
      end
    end

    context "when the effective_from is moved before today" do
      let(:params) { {effective_from: 1.day.ago.beginning_of_day.iso8601} }

      before { allow(Utils::ActivityLog).to receive(:available?).and_return(true) }

      it "returns a validation failure and leaves the rate pending" do
        expect(result).not_to be_success
        expect(result.error.messages[:effective_from]).to eq(["must_not_be_before_today"])
        expect(rate_card_rate.reload.status).to eq("pending")
      end

      it "does not enqueue a webhook" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)
      end

      it "does not deliver an activity event", :capture_kafka_messages do
        expect(result).not_to be_success
        expect(kafka_messages).to be_empty
      end
    end

    context "when the effective_from carries a time component on an arrears card" do
      let(:params) { {effective_from: 2.months.from_now.change(hour: 17).iso8601} }

      it "canonicalizes the value to its day's midnight" do
        expect(result).to be_success
        expect(result.rate_card_rate.effective_from).to eq(2.months.from_now.beginning_of_day)
      end
    end

    context "when the catalog flag is disabled" do
      let(:organization) { create(:organization) }

      it "still schedules the pair for an unguarded direct service call" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("rate_card_rate.updated", rate_card_rate)
        rate = result.rate_card_rate
        expect(Utils::ActivityLog).to have_received(:produce).with(rate, "rate_card_rate.updated", after_commit: true)
      end
    end

    context "when no attributes change" do
      let(:params) { {} }

      it "publishes both event channels" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("rate_card_rate.updated", rate_card_rate)
        expect(result).to be_success
        expect(Utils::ActivityLog).to have_received(:produce).with(rate_card_rate, "rate_card_rate.updated", after_commit: true)
      end
    end

    context "when resending the same arrears day with a non-midnight time" do
      let(:params) { {effective_from: rate_card_rate.effective_from.change(hour: 17).iso8601} }

      it "publishes both event channels after date normalization" do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("rate_card_rate.updated", rate_card_rate)
        expect(result).to be_success
        expect(rate_card_rate.reload.effective_from).to eq(params[:effective_from].to_time.beginning_of_day)
        expect(Utils::ActivityLog).to have_received(:produce).with(rate_card_rate, "rate_card_rate.updated", after_commit: true)
      end
    end

    context "when the surrounding transaction rolls back" do
      before do
        rate_card_rate
        allow(Utils::ActivityLog).to receive(:available?).and_return(true)
      end

      it "suppresses both event channels", :capture_kafka_messages, transaction: false do
        expect do
          ActiveRecord::Base.transaction do
            expect(result).to be_success
            raise ActiveRecord::Rollback
          end
        end.not_to have_enqueued_job(SendWebhookJob)

        expect(rate_card_rate.reload.rate_properties).to eq("amount" => "10")
        expect(kafka_messages).to be_empty
      end
    end
  end

  context "with an active rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day)
    end

    context "when updating rate_properties" do
      let(:params) { {rate_properties: {"amount" => "42"}} }

      it "updates the properties" do
        expect(result).to be_success
        expect(result.rate_card_rate.rate_properties).to eq("amount" => "42")
      end
    end

    context "when updating a frozen field" do
      let(:params) { {billing_interval_count: 6} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_interval_count]).to eq(["not_editable_on_active_rate"])
      end
    end
  end

  context "with a terminated rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 2.months.ago.beginning_of_day)
    end

    let(:params) { {rate_properties: {"amount" => "42"}} }

    before do
      rate_card_rate
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day)
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:status]).to eq(["terminated_rate_not_editable"])
    end
  end

  context "when rate_card_rate is nil" do
    let(:rate_card_rate) { nil }
    let(:params) { {} }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card_rate")
    end
  end

  describe "code editability" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day)
    end
    let(:params) { {code: "after"} }

    it "updates the code when the card is not attached" do
      expect { result }.to change { rate_card_rate.reload.code }.to("after")
    end

    context "when the card is attached to a plan" do
      before { create(:plan_rate_card, organization:, rate_card:) }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:code]).to eq(["attached_to_plan_or_subscription"])
      end

      it "still accepts a payload resending the current code" do
        update_result = described_class.call(rate_card_rate:, params: {code: rate_card_rate.code, rate_properties: {"amount" => "9"}})

        expect(update_result).to be_success
        expect(update_result.rate_card_rate.rate_properties).to eq("amount" => "9")
      end
    end
  end

  context "when the card is attached to a subscription" do
    let(:params) { {rate_properties: {"amount" => "25"}} }

    before { create(:contract_rate_card, organization:, rate_card:) }

    context "with a pending rate" do
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
      end

      it "updates the rate" do
        expect(result).to be_success
        expect(result.rate_card_rate.rate_properties).to eq("amount" => "25")
      end
    end

    context "with an active rate" do
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day)
      end

      it "forbids updating the rate" do
        expect(result).not_to be_success
        expect(result.error.messages[:rate_card]).to include("attached_to_subscriptions")
      end
    end
  end
end
