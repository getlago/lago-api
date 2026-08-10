# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCards::CreateService do
  subject(:result) { described_class.call(product:, params:) }

  let(:organization) { create(:organization) }
  # The shared params set proration: true, which requires a recurring metric.
  let(:metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", recurring: true, field_name: "amount") }
  let(:product) { create(:product, organization:, billable_metric: metric) }

  let(:params) do
    {
      name: "Growth USD",
      code: "growth_usd",
      description: "Growth tier pricing in USD",
      currency: "USD",
      billing_timing: "arrears",
      proration: true
    }
  end

  it "creates a rate card" do
    expect { result }.to change(RateCard, :count).by(1)

    rate_card = result.rate_card
    expect(rate_card.product).to eq(product)
    expect(rate_card.name).to eq("Growth USD")
    expect(rate_card.code).to eq("growth_usd")
    expect(rate_card.currency).to eq("USD")
    expect(rate_card.billing_timing).to eq("arrears")
    expect(rate_card.display_on_invoice).to be(true)
    expect(rate_card.regroup_paid_fees).to eq("none")
  end

  context "when regroup_paid_fees is explicitly null" do
    before { params[:regroup_paid_fees] = nil }

    it "falls back to none instead of inserting NULL" do
      expect(result.rate_card.regroup_paid_fees).to eq("none")
    end
  end

  context "when proration is omitted" do
    let(:params) { {name: "No proration", code: "no_proration", currency: "USD"} }

    it "falls back to the column default" do
      expect(result.rate_card.proration).to be(false)
    end
  end

  context "when proration is explicitly null" do
    before { params[:proration] = nil }

    it "falls back to the column default instead of inserting NULL" do
      expect(result).to be_success
      expect(result.rate_card.proration).to be(false)
    end
  end

  context "when proration is not a boolean" do
    before { params[:proration] = "hello" }

    it "returns a validation failure instead of coercing to true" do
      expect(result).not_to be_success
      expect(result.error.messages[:proration]).to eq(["value_is_invalid"])
    end
  end

  it "produces an activity log" do
    rate_card = result.rate_card
    expect(Utils::ActivityLog).to have_produced("rate_card.created").after_commit.with(rate_card)
  end

  context "with nested rates" do
    # A prorated card requires a recurring metric for its rates to be valid.
    let(:product) do
      metric = create(:billable_metric, organization:, aggregation_type: "sum_agg", recurring: true, field_name: "amount")
      create(:product, organization:, billable_metric: metric)
    end

    before do
      params[:rates] = [
        {
          code: "launch_price",
          effective_from: 1.minute.ago.beginning_of_day.iso8601,
          rate_model: "standard",
          rate_properties: {"amount" => "10"},
          billing_interval_unit: "month"
        },
        {
          code: "standard_price",
          effective_from: 1.month.from_now.beginning_of_day.iso8601,
          rate_model: "standard",
          rate_properties: {"amount" => "12"},
          billing_interval_unit: "month"
        }
      ]
    end

    it "creates the card with its rates in one call" do
      expect { result }.to change(RateCardRate, :count).by(2)

      rates = result.rate_card.rates.order(:effective_from)
      expect(rates.first.status).to eq("active")
      expect(rates.last.status).to eq("pending")
    end

    it "does not produce per-rate activity logs" do
      result
      expect(Utils::ActivityLog).not_to have_produced("rate_card.updated")
    end

    context "when a nested rate is invalid" do
      before { params[:rates] = [{code: "bad", rate_model: "standard", rate_properties: {}, billing_interval_unit: "month", effective_from: Time.current.beginning_of_day.iso8601}] }

      it "returns a validation failure with prefixed keys and creates nothing" do
        expect { result }.not_to change(RateCard, :count)
        expect(result).not_to be_success
        expect(result.error.messages[:"rates.rate_properties"]).to be_present
      end
    end
  end

  context "with a product filter" do
    let(:filter) { create(:product_filter, organization:, product:) }

    before { params[:product_filter_id] = filter.id }

    it "scopes the card to the filter" do
      expect(result.rate_card.product_filter).to eq(filter)
    end

    context "when the filter belongs to another product" do
      let(:filter) { create(:product_filter, organization:) }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("product_filter")
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

  context "when the code is already used on the product" do
    before { create(:rate_card, organization:, product:, code: "growth_usd") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end

  context "when product is nil" do
    let(:product) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
    end
  end
end
