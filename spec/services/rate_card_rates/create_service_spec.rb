# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRates::CreateService do
  subject(:result) { described_class.call(rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:params) do
    {
      code: "standard_price",
      effective_from: Time.current.beginning_of_day.iso8601,
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
    expect(rate.code).to eq("standard_price")
  end

  context "when the code is missing" do
    before { params.delete(:code) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end

  it "produces a rate_card.updated activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("rate_card.updated").after_commit.with(rate_card)
  end

  context "when effective_from is in the future" do
    before { params[:effective_from] = 1.month.from_now.beginning_of_day.iso8601 }

    it "creates a pending rate" do
      expect(result.rate_card_rate.status).to eq("pending")
    end
  end

  context "with an arrears card" do
    it "canonicalizes a datetime to its day's midnight" do
      params[:effective_from] = 1.month.from_now.change(hour: 17).iso8601

      expect(result).to be_success
      expect(result.rate_card_rate.effective_from).to eq(1.month.from_now.beginning_of_day)
    end

    it "accepts a bare date" do
      params[:effective_from] = 1.month.from_now.to_date.iso8601

      expect(result).to be_success
      expect(result.rate_card_rate.effective_from).to eq(1.month.from_now.beginning_of_day)
    end

    it "refuses a second rate on the same day whatever its time" do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.from_now.beginning_of_day)
      params[:effective_from] = 1.month.from_now.change(hour: 17).iso8601

      expect(result).not_to be_success
      expect(result.error.messages[:effective_from]).to eq(["value_already_exist"])
    end
  end

  context "with an advance card" do
    let(:rate_card) { create(:rate_card, organization:, billing_timing: "advance") }

    it "keeps the full instant" do
      effective_at = 1.month.from_now.change(hour: 17)
      params[:effective_from] = effective_at.iso8601

      expect(result).to be_success
      expect(result.rate_card_rate.effective_from).to eq(effective_at)
    end

    it "converts a bare date to midnight" do
      params[:effective_from] = 1.month.from_now.to_date.iso8601

      expect(result).to be_success
      expect(result.rate_card_rate.effective_from).to eq(1.month.from_now.beginning_of_day)
    end
  end

  context "when a rate is already active" do
    let!(:previous_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day) }

    it "terminates the previous rate and activates the new one" do
      expect(result.rate_card_rate.status).to eq("active")
      expect(previous_rate.reload.status).to eq("terminated")
    end
  end

  context "when the effective_from is at or before the active rate" do
    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.day.ago.beginning_of_day)
      params[:effective_from] = 2.days.ago.beginning_of_day.iso8601
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:effective_from]).to eq(["must_be_after_active_rate"])
    end
  end

  context "when the effective_from falls between the active rate and a pending rate" do
    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: 1.day.ago.beginning_of_day)
      create(:rate_card_rate, organization:, rate_card:, effective_from: 30.days.from_now.beginning_of_day)
      params[:effective_from] = 10.days.from_now.beginning_of_day.iso8601
    end

    it "creates the rate in the pending sequence" do
      expect(result).to be_success
      expect(result.rate_card_rate.status).to eq("pending")
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

  context "when the card is attached to a subscription" do
    before { create(:contract_rate_card, organization:, rate_card:) }

    it "appends the rate" do
      expect(result).to be_success
      expect(result.rate_card_rate).to be_persisted
    end

    context "when the rate is not after the active rate" do
      before { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.month.ago.beginning_of_day) }

      it "still enforces the timeline placement" do
        params[:effective_from] = 2.months.ago.beginning_of_day.iso8601

        expect(result).not_to be_success
        expect(result.error.messages[:effective_from]).to eq(["must_be_after_active_rate"])
      end
    end
  end

  context "when the card is on a plan that has subscriptions" do
    before do
      plan = create(:plan, organization:)
      create(:plan_rate_card, organization:, plan:, rate_card:)
      create(:subscription, plan:, organization:)
    end

    it "appends the rate" do
      expect(result).to be_success
      expect(result.rate_card_rate).to be_persisted
    end
  end

  context "when a graduated percentage rate has no ranges" do
    let(:params) do
      {
        code: "gp",
        effective_from: Time.current,
        rate_model: "graduated_percentage",
        rate_properties: {},
        billing_interval_unit: "month"
      }
    end

    it "returns a validation failure instead of raising" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_properties]).to be_present
    end
  end
end
