# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCards::CreateService do
  subject(:result) { described_class.call(plan:, params:) }

  let_it_be(:organization) { create(:organization) }

  before_all do
    create_default(:billable_metric)
  end

  let_it_be(:plan) { create(:plan, :product_catalog, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }

  let(:params) { {rate_card_code: rate_card.code, units: "10"} }

  it "creates a plan product" do
    expect { result }.to change(PlanRateCard, :count).by(1)

    plan_rate_card = result.plan_rate_card
    expect(plan_rate_card.plan).to eq(plan)
    expect(plan_rate_card.rate_card).to eq(rate_card)
    expect(plan_rate_card.units).to eq(10)
  end

  it "creates a default rate phase" do
    expect { result }.to change(RatePhase, :count).by(1)

    rate_phase = result.plan_rate_card.rate_phases.first
    expect(rate_phase.position).to eq(1)
    expect(rate_phase.billing_interval_cycle_count).to be_nil
    expect(rate_phase.contract_rate_card_id).to be_nil
  end

  context "when the plan already prices the whole item" do
    before { create(:plan_rate_card, organization:, plan:, rate_card: create(:rate_card, organization:, product: rate_card.product)) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_card]).to eq(["product_already_priced"])
    end
  end

  context "when the plan already prices the same filter slice" do
    let(:product) { create(:product, organization:) }
    let(:filter) { create(:product_filter, organization:, product:) }
    let(:rate_card) { create(:rate_card, organization:, product:, product_filter: filter) }

    before { create(:plan_rate_card, organization:, plan:, rate_card: create(:rate_card, organization:, product:, product_filter: filter)) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:rate_card]).to eq(["product_filter_already_priced"])
    end
  end

  context "when the plan prices a different slice of the same item" do
    before do
      filter = create(:product_filter, organization:, product: rate_card.product)
      scoped_card = create(:rate_card, organization:, product: rate_card.product, product_filter: filter)
      create(:plan_rate_card, organization:, plan:, rate_card: scoped_card)
    end

    it "creates the entry" do
      expect(result).to be_success
    end
  end

  context "when the rate card currency does not match the plan currency" do
    let(:rate_card) { create(:rate_card, organization:, currency: "USD") }

    it "rejects the attachment at configuration time" do
      expect { result }.not_to change(PlanRateCard, :count)

      expect(result).not_to be_success
      expect(result.error.messages[:currency]).to eq(["currency_does_not_match"])
    end
  end

  context "when the plan is a legacy plan" do
    let(:plan) { create(:plan, organization:) }

    it "rejects the attachment" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["legacy_plan"])
    end
  end

  context "with a nested rate_phases sequence" do
    let(:params) do
      {
        rate_card_code: rate_card.code,
        units: "1",
        rate_phases: [
          {code: "launch", position: 1, name: "Launch", billing_interval_cycle_count: 3},
          {code: "standard", position: 2, name: "Standard", billing_interval_cycle_count: nil}
        ]
      }
    end

    it "creates the entry with the provided phases instead of the default" do
      expect(result).to be_success
      expect(result.plan_rate_card.rate_phases.order(:position).pluck(:name)).to eq(%w[Launch Standard])
    end
  end

  context "with an invalid nested rate_phases sequence" do
    let(:params) do
      {
        rate_card_code: rate_card.code,
        rate_phases: [
          {code: "launch", position: 1, billing_interval_cycle_count: 3},
          {code: "standard", position: 3, billing_interval_cycle_count: nil}
        ]
      }
    end

    it "fails and rolls the whole create back" do
      expect { result }.not_to change(PlanRateCard, :count)
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to eq(["positions_must_be_contiguous"])
    end
  end

  context "with an explicit empty rate_phases list" do
    let(:params) { {rate_card_code: rate_card.code, rate_phases: []} }

    it "rejects it instead of silently creating the default phase" do
      expect { result }.not_to change(PlanRateCard, :count)
      expect(result).not_to be_success
      expect(result.error.messages[:rate_phases]).to eq(["value_is_mandatory"])
    end
  end

  context "when the plan is missing" do
    let(:plan) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the rate card does not exist" do
    let(:params) { {rate_card_code: "unknown"} }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end

  context "when the plan has subscriptions" do
    before { create(:subscription, plan:, organization:) }

    it "forbids adding a rate card" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["plan_locked"])
    end
  end
end
