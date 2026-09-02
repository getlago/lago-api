# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::CreateService do
  subject(:result) { described_class.call(organization:, params:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, :product_catalog, organization:) }

  let(:params) do
    {
      external_customer_id: customer.external_id,
      external_id: "contract-1",
      plan_code: plan.code
    }
  end

  it "creates an active contract on the plan and materializes its rate cards" do
    rate_card = create(:rate_card, organization:)
    create(:plan_rate_card, organization:, plan:, rate_card:, units: 5)

    expect { result }.to change(Contract, :count).by(1).and change(ContractRateCard, :count).by(1)

    contract = result.contract
    expect(contract).to have_attributes(
      customer:,
      plan:,
      external_id: "contract-1",
      status: "active",
      billing_time: "calendar"
    )
    expect(contract.started_at).to be_within(5.seconds).of(Time.current)
    expect(contract.applied_rate_cards.sole).to have_attributes(rate_card:, units: 5)
  end

  context "without a plan" do
    let(:params) { {external_customer_id: customer.external_id, external_id: "contract-1"} }

    it "creates a plan-less contract with no rate cards" do
      expect { result }.to change(Contract, :count).by(1)

      expect(result.contract.plan).to be_nil
      expect(result.contract.applied_rate_cards).to be_empty
    end
  end

  context "when the contract starts in the future" do
    let(:params) { super().merge(started_at: 1.month.from_now.iso8601) }

    it "creates a pending contract" do
      expect(result).to be_success
      expect(result.contract.status).to eq("pending")
      expect(result.contract.started_at).to be_within(5.seconds).of(1.month.from_now)
    end
  end

  context "with explicit dates" do
    let(:params) do
      super().merge(
        started_at: "2026-10-01T00:00:00Z",
        ended_at: "2027-09-30T23:59:59Z",
        billing_anchor_date: "2026-10-15"
      )
    end

    it "stores the validity window and the anchor" do
      contract = result.contract

      expect(contract.started_at).to eq(Time.zone.parse("2026-10-01"))
      expect(contract.ended_at).to eq(Time.zone.parse("2027-09-30T23:59:59Z"))
      expect(contract.billing_anchor_date).to eq(Date.new(2026, 10, 15))
    end
  end

  context "with a malformed date" do
    let(:params) { super().merge(billing_anchor_date: "hello") }

    it "returns a validation failure instead of silently dropping it" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_anchor_date]).to eq(["value_is_invalid"])
    end
  end

  context "when ended_at is before started_at" do
    let(:params) { super().merge(started_at: 2.months.from_now.iso8601, ended_at: 1.month.from_now.iso8601) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:ended_at]).to eq(["must_be_after_started_at"])
    end
  end

  context "when the window already closed" do
    let(:params) { super().merge(started_at: 2.months.ago.iso8601, ended_at: 1.month.ago.iso8601) }

    it "rejects the already-ended contract" do
      expect(result).not_to be_success
      expect(result.error.messages[:ended_at]).to eq(["already_ended"])
    end
  end

  context "when the customer does not exist" do
    let(:params) { super().merge(external_customer_id: "unknown") }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("customer")
    end
  end

  context "when the plan does not exist" do
    let(:params) { super().merge(plan_code: "unknown") }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("plan")
    end
  end

  context "when the plan is a legacy plan" do
    let(:plan) { create(:plan, organization:) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:plan]).to eq(["not_a_product_catalog_plan"])
    end
  end

  context "when a live contract already uses the external id" do
    before { create(:contract, organization:, customer:, external_id: "contract-1") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:external_id]).to eq(["value_already_exists"])
    end
  end

  context "when a terminated contract used the external id" do
    before { create(:contract, :terminated, organization:, customer:, external_id: "contract-1") }

    it "creates the new contract" do
      expect(result).to be_success
    end
  end

  context "with an invalid billing_time" do
    let(:params) { super().merge(billing_time: "weekly") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:billing_time]).to be_present
    end
  end

  context "without an external_id" do
    let(:params) { super().merge(external_id: nil) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:external_id]).to be_present
    end
  end
end
