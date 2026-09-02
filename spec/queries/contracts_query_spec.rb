# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractsQuery do
  subject(:result) { described_class.call(organization:, pagination: nil, filters:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, :product_catalog, organization:) }
  let(:filters) { {} }

  let!(:contract) { create(:contract, organization:, customer:, plan:) }
  let!(:other_contract) { create(:contract, organization:) }

  before { create(:contract) }

  it "returns the organization's contracts only" do
    expect(result.contracts).to contain_exactly(contract, other_contract)
  end

  context "when filtering by external_customer_id" do
    let(:filters) { {external_customer_id: customer.external_id} }

    it "returns the customer's contracts" do
      expect(result.contracts).to contain_exactly(contract)
    end
  end

  context "when filtering by plan_code" do
    let(:filters) { {plan_code: plan.code} }

    it "returns the plan's contracts" do
      expect(result.contracts).to contain_exactly(contract)
    end
  end

  context "when filtering by external_id" do
    let(:filters) { {external_id: contract.external_id} }

    it "returns the matching contracts" do
      expect(result.contracts).to contain_exactly(contract)
    end
  end

  context "when filtering by status" do
    let(:filters) { {status: ["pending"]} }
    let!(:pending_contract) { create(:contract, :pending, organization:) }

    before { create(:contract, :terminated, organization:) }

    it "returns the matching contracts" do
      expect(result.contracts).to contain_exactly(pending_contract)
    end
  end

  context "when filtering by an unknown status" do
    let(:filters) { {status: ["bogus"]} }

    it "matches nothing instead of raising on the enum cast" do
      expect(result.contracts).to be_empty
    end
  end
end
