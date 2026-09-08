# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::UpdateService do
  subject(:result) { described_class.call(contract:, params:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

  let(:params) { {name: "Renamed", billing_time: "anniversary"} }

  it "updates the editable authoring fields" do
    expect(result).to be_success
    expect(contract.reload).to have_attributes(name: "Renamed", billing_time: "anniversary")
  end

  it "sets the window dates in the customer timezone" do
    result = described_class.call(contract:, params: {started_at: "2026-11-01T00:00:00", ended_at: "2026-12-01T00:00:00"})

    expect(result).to be_success
    expect(contract.reload.started_at).to eq(Time.zone.parse("2026-11-01T00:00:00"))
    expect(contract.ended_at).to eq(Time.zone.parse("2026-12-01T00:00:00"))
  end

  context "when the contract is already active" do
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    it "rejects the edit as locked" do
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
    end
  end

  context "when the contract is missing" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when changing the plan" do
    let(:new_rate_card) { create(:rate_card, organization:) }
    let(:other_plan) { create(:catalog_plan, organization:) }
    let(:params) { {plan_code: other_plan.code} }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:))
      create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: new_rate_card, units: 3)
    end

    it "re-materializes the rate cards from the new plan" do
      expect(result).to be_success
      expect(contract.reload.catalog_plan).to eq(other_plan)
      expect(contract.applied_rate_cards.sole).to have_attributes(rate_card: new_rate_card, units: 3)
    end
  end

  context "when the plan code is unknown" do
    let(:params) { {plan_code: "unknown"} }

    it "returns a not found plan failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "with a malformed date" do
    let(:params) { {started_at: "not-a-date"} }

    it "rejects the value" do
      expect(result).not_to be_success
      expect(result.error.messages[:started_at]).to eq(["value_is_invalid"])
    end
  end

  context "when the end date is already in the past" do
    let(:params) { {ended_at: 1.day.ago.iso8601} }

    it "rejects the ended_at" do
      expect(result).not_to be_success
      expect(result.error.messages[:ended_at]).to eq(["already_ended"])
    end
  end
end
