# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRates::UpdateService do
  subject(:result) { described_class.call(rate_card_rate:, params:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

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

    it "produces a rate_card.updated activity log" do
      result
      expect(Utils::ActivityLog).to have_produced("rate_card.updated").after_commit.with(rate_card)
    end

    context "when the effective_from is moved to the past" do
      let(:params) { {effective_from: Time.current.beginning_of_day.iso8601} }

      it "activates the rate" do
        expect(result).to be_success
        expect(result.rate_card_rate.status).to eq("active")
      end
    end

    context "when the effective_from carries a time component on an arrears card" do
      let(:params) { {effective_from: 2.months.from_now.change(hour: 17).iso8601} }

      it "canonicalizes the value to its day's midnight" do
        expect(result).to be_success
        expect(result.rate_card_rate.effective_from).to eq(2.months.from_now.beginning_of_day)
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
