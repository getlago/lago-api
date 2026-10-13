# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractsQuery do
  subject(:result) { described_class.call(organization:, pagination: nil, filters:, search_term:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:filters) { {} }
  let(:search_term) { nil }

  let!(:contract) { create(:contract, organization:, customer:, catalog_plan:) }
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
    let(:filters) { {plan_code: catalog_plan.code} }

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

  context "when filtering by billing_entity_ids" do
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:filters) { {billing_entity_ids: [billing_entity.id]} }

    let!(:direct_contract) { create(:contract, organization:, billing_entity:) }
    let!(:inherited_contract) do
      create(:contract, organization:, customer: create(:customer, organization:, billing_entity:))
    end

    it "matches the contract's own entity and the one inherited from its customer" do
      expect(result.contracts).to contain_exactly(direct_contract, inherited_contract)
    end
  end

  context "when filtering by has_rate_overrides" do
    # One contract whose phase carries an override, and a sibling whose phase
    # exists but carries none — so the filter is exercised against a real
    # non-overriding phase, not merely the absence of any rate card.
    let!(:overridden_contract) do
      contract.tap do |c|
        card = create(:contract_rate_card, organization:, contract: c)
        create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card: card, rate_override: create(:rate_override, organization:))
      end
    end
    let!(:plain_phase_contract) do
      other_contract.tap do |c|
        card = create(:contract_rate_card, organization:, contract: c)
        create(:rate_phase, organization:, plan_rate_card: nil, contract_rate_card: card, rate_override_id: nil)
      end
    end

    context "when true" do
      let(:filters) { {has_rate_overrides: true} }

      it "returns only contracts carrying an override" do
        expect(result.contracts).to contain_exactly(overridden_contract)
      end
    end

    context "when false" do
      let(:filters) { {has_rate_overrides: false} }

      it "returns contracts with no override" do
        expect(result.contracts).to contain_exactly(plain_phase_contract)
      end
    end
  end

  context "when searching" do
    let(:search_term) { "acme" }

    it "matches on the contract external id" do
      match = create(:contract, organization:, external_id: "acme-contract")

      expect(result.contracts).to contain_exactly(match)
    end

    it "matches on the contract name" do
      match = create(:contract, organization:, name: "ACME agreement")

      expect(result.contracts).to contain_exactly(match)
    end

    it "matches on the plan name or code" do
      plan = create(:catalog_plan, organization:, name: "Acme plan")
      match = create(:contract, organization:, catalog_plan: plan)

      expect(result.contracts).to contain_exactly(match)
    end

    it "matches on the customer" do
      acme_customer = create(:customer, organization:, name: "Acme Inc")
      match = create(:contract, organization:, customer: acme_customer)

      expect(result.contracts).to contain_exactly(match)
    end

    it "matches on the contract id when the term is a uuid" do
      match = create(:contract, organization:)
      result = described_class.call(organization:, pagination: nil, filters: {}, search_term: match.id)

      expect(result.contracts).to contain_exactly(match)
    end

    it "ignores the search term when an external_id filter is present" do
      result = described_class.call(
        organization:, pagination: nil, filters: {external_id: contract.external_id}, search_term: "no-such-match"
      )

      expect(result.contracts).to contain_exactly(contract)
    end
  end
end
