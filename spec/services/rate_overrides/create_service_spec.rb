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
end
