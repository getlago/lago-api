# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCards::UpdateService do
  subject(:result) { described_class.call(rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:, name: "Before", currency: "EUR") }

  let(:params) { {name: "After", description: "new", billing_timing: "advance"} }

  it "updates the attributes" do
    expect(result).to be_success
    expect(result.rate_card.name).to eq("After")
    expect(result.rate_card.description).to eq("new")
    expect(result.rate_card.billing_timing).to eq("advance")
  end

  it "does not change the code" do
    expect { result }.not_to change { rate_card.reload.code }
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("rate_card.updated").after_commit.with(rate_card)
  end

  context "when the card has no rates" do
    let(:params) { {currency: "USD"} }

    it "allows changing the currency" do
      expect(result).to be_success
      expect(result.rate_card.currency).to eq("USD")
    end
  end

  context "when the card has rates" do
    before { create(:rate_card_rate, organization:, rate_card:) }

    context "when changing the currency" do
      let(:params) { {currency: "USD"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:currency]).to eq(["not_editable_with_rates"])
      end
    end

    context "when sending the unchanged currency" do
      let(:params) { {currency: "EUR", name: "After"} }

      it "is allowed" do
        expect(result).to be_success
        expect(result.rate_card.name).to eq("After")
      end
    end
  end

  context "when rate_card is nil" do
    let(:rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end
end
