# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::CreateService do
  subject(:result) { described_class.call(**attributes) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let(:started_at) { Time.zone.parse("2026-10-01") }
  let(:planned_operation) do
    build_planned_operation(cycle_started_at: started_at, billing_at: started_at)
  end
  let(:attributes) do
    {
      contract_rate_card:, action_type: "renew_fixed_advance", causation_type: :contract_activation,
      planned_operation:
    }
  end

  def build_planned_operation(cycle_started_at:, billing_at:)
    BillingOperations::Schedule::PlannedOperation.new(
      cycle_started_at:, billing_at:
    )
  end

  it "creates an operation with its due and target cycle dates" do
    expect(result).to be_success
    expect(result.operation).to have_attributes(
      organization: contract_rate_card.organization, customer: contract_rate_card.contract.customer,
      contract_rate_card:, billing_at: started_at,
      target_cycle_started_at: started_at
    )
  end

  it "allows duplicate operations to be created" do
    existing = described_class.call(**attributes).operation

    expect(result).to be_success
    expect(result.operation).not_to eq(existing)
    expect(contract_rate_card.billing_operations.count).to eq(2)
  end

  context "when the contract rate card is missing" do
    let(:attributes) { super().merge(contract_rate_card: nil) }

    it "returns a not found failure" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(BillingOperation.count).to eq(0)
    end
  end
end
