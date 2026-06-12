# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRates::CreateService do
  subject(:result) { described_class.call(rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:params) do
    {
      effective_datetime: Time.current.iso8601,
      rate_model: "standard",
      rate_properties: {"amount" => "10"},
      billing_interval_count: 1,
      billing_interval_unit: "month"
    }
  end

  it "creates an active rate when effective now" do
    expect { result }.to change(RateCardRate, :count).by(1)

    rate = result.rate_card_rate
    expect(rate.rate_model).to eq("standard")
    expect(rate.status).to eq("active")
  end

  it "produces a rate_card.updated activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("rate_card.updated").after_commit.with(rate_card)
  end

  context "when effective_datetime is in the future" do
    before { params[:effective_datetime] = 1.month.from_now.iso8601 }

    it "creates a pending rate" do
      expect(result.rate_card_rate.status).to eq("pending")
    end
  end

  context "when a rate is already active" do
    let!(:previous_rate) { create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.month.ago) }

    it "terminates the previous rate and activates the new one" do
      expect(result.rate_card_rate.status).to eq("active")
      expect(previous_rate.reload.status).to eq("terminated")
    end
  end

  context "when the effective_datetime is before the latest rate" do
    before do
      create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.day.from_now)
      params[:effective_datetime] = Time.current.iso8601
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:effective_datetime]).to be_present
    end
  end

  context "when rate_properties do not match the rate model" do
    before { params[:rate_properties] = {} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_properties]).to be_present
    end
  end

  context "when the card has a pricing unit and no conversion rate is given" do
    let(:rate_card) { create(:rate_card, organization:, applied_pricing_unit_code: "credits") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:applied_pricing_unit_conversion_rate]).to be_present
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
