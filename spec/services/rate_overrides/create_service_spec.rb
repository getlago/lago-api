# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateOverrides::CreateService do
  subject(:result) { described_class.call(rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:params) do
    {
      rate_model: "standard",
      rate_properties: {"amount" => "5"},
      min_amount_cents: 100,
      billing_interval_count: 1,
      billing_interval_unit: "month"
    }
  end

  it "creates a rate override" do
    expect { result }.to change(RateOverride, :count).by(1)

    rate_override = result.rate_override
    expect(rate_override.organization).to eq(organization)
    expect(rate_override.rate_model).to eq("standard")
    expect(rate_override.rate_properties).to eq({"amount" => "5"})
    expect(rate_override.min_amount_cents).to eq(100)
  end

  context "with a spend floor on an advance card" do
    let(:rate_card) { create(:rate_card, organization:, billing_timing: "advance") }

    it "rejects it like the rate layer does" do
      expect { result }.not_to change(RateOverride, :count)

      expect(result).not_to be_success
      expect(result.error.messages[:min_amount_cents]).to eq(["not_allowed_for_billing_timing"])
    end

    it "accepts a zero floor" do
      zero = described_class.call(rate_card:, params: params.merge(min_amount_cents: 0))

      expect(zero).to be_success
    end
  end

  context "with a structural card field" do
    it "rejects each field on its own key instead of silently dropping it" do
      {billing_timing: "advance", currency: "EUR", proration: true}.each do |field, value|
        result = described_class.call(rate_card:, params: params.merge(field => value))

        expect(result).not_to be_success
        expect(result.error.messages[field]).to eq(["not_overridable"])
      end
    end

    it "creates nothing" do
      expect { described_class.call(rate_card:, params: params.merge(currency: "EUR")) }
        .not_to change(RateOverride, :count)
    end
  end

  it "defaults min_amount_cents and rate_properties" do
    result = described_class.call(rate_card:, params: {rate_model: "standard", rate_properties: {"amount" => "5"}})

    expect(result.rate_override.min_amount_cents).to eq(0)
  end

  context "when the rate card is missing" do
    let(:rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end

  context "when the rate properties are invalid for the model" do
    let(:params) { {rate_model: "graduated", rate_properties: {}} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to have_key(:rate_properties)
    end

    context "with a graduated percentage model" do
      let(:params) { {rate_model: "graduated_percentage", rate_properties: {}} }

      it "returns a validation failure instead of raising" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to have_key(:rate_properties)
      end
    end
  end

  context "when the card carries a pricing unit" do
    let(:rate_card) { create(:rate_card, organization:, applied_pricing_unit_code: "credits") }

    it "requires a pricing_unit_conversion_rate" do
      expect(result).not_to be_success
      expect(result.error.messages[:pricing_unit_conversion_rate]).to include("value_is_mandatory")
    end

    it "succeeds when the conversion rate is provided" do
      result = described_class.call(rate_card:, params: params.merge(pricing_unit_conversion_rate: "2.5"))

      expect(result).to be_success
      expect(result.rate_override.pricing_unit_conversion_rate).to eq(2.5)
    end
  end

  context "when the rate model is incompatible with the card" do
    let(:product) { create(:product, organization:, product_type: "fixed", billable_metric: nil) }
    let(:rate_card) { create(:rate_card, organization:, product:) }
    let(:params) { {rate_model: "percentage", rate_properties: {rate: "1"}} }

    it "returns a scoped validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_model]).to eq(["not_allowed_for_product"])
    end
  end
end
