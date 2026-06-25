# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCards::CreateService do
  subject(:result) { described_class.call(product_item:, params:) }

  let(:organization) { create(:organization) }
  let(:product_item) { create(:product_item, organization:) }

  let(:params) do
    {
      name: "Growth USD",
      code: "growth_usd",
      description: "Growth tier pricing in USD",
      currency: "USD",
      billing_timing: "arrears",
      proration: "full"
    }
  end

  it "creates a rate card" do
    expect { result }.to change(RateCard, :count).by(1)

    rate_card = result.rate_card
    expect(rate_card.product_item).to eq(product_item)
    expect(rate_card.name).to eq("Growth USD")
    expect(rate_card.code).to eq("growth_usd")
    expect(rate_card.currency).to eq("USD")
    expect(rate_card.billing_timing).to eq("arrears")
    expect(rate_card.display_on_invoice).to be(true)
  end

  it "produces an activity log" do
    rate_card = result.rate_card
    expect(Utils::ActivityLog).to have_produced("rate_card.created").after_commit.with(rate_card)
  end

  context "with a product item filter" do
    let(:filter) { create(:product_item_filter, organization:, product_item:) }

    before { params[:product_item_filter_id] = filter.id }

    it "scopes the card to the filter" do
      expect(result.rate_card.product_item_filter).to eq(filter)
    end

    context "when the filter belongs to another product item" do
      let(:filter) { create(:product_item_filter, organization:) }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("product_item_filter")
      end
    end
  end

  context "when wallet_targetable is set without the organization feature" do
    before { params[:wallet_targetable] = true }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:wallet_targetable]).to eq(["feature_unavailable"])
    end
  end

  context "when applied_pricing_unit_code is unknown" do
    before { params[:applied_pricing_unit_code] = "unknown" }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:applied_pricing_unit_code]).to eq(["value_is_invalid"])
    end
  end

  context "when the code is already used on the product item" do
    before { create(:rate_card, organization:, product_item:, code: "growth_usd") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end

  context "when product_item is nil" do
    let(:product_item) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_item")
    end
  end
end
