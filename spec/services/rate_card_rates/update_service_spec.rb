# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRates::UpdateService do
  subject(:result) { described_class.call(rate_card_rate:, params:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  context "with a pending rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.from_now)
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

    context "when the effective_datetime is moved to the past" do
      let(:params) { {effective_datetime: Time.current.iso8601} }

      it "activates the rate" do
        expect(result).to be_success
        expect(result.rate_card_rate.status).to eq("active")
      end
    end
  end

  context "with an active rate" do
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.ago)
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
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 2.months.ago)
    end

    let(:params) { {rate_properties: {"amount" => "42"}} }

    before do
      rate_card_rate
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.ago)
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
end
