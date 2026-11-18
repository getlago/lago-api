# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ContractEntitlementSerializer do
  subject(:payload) { described_class.new(contract_entitlement).serialize }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:) }
  let_it_be(:contract) { create(:contract, organization:, catalog_plan:, external_id: "contract_123") }
  let_it_be(:seats) { create(:feature, organization:, code: "seats") }
  let_it_be(:seats_sso) { create(:privilege, organization:, feature: seats, code: "sso", value_type: "boolean", created_at: 2.days.ago) }
  let_it_be(:seats_max) { create(:privilege, organization:, feature: seats, code: "max", value_type: "integer", created_at: 1.day.ago) }

  let(:contract_entitlements) { Entitlement::SubscriptionEntitlement.for_contract(contract) }
  let(:contract_entitlement) { contract_entitlements.find { it.code == "seats" } }

  before do
    plan_entitlement = create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: seats)
    create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: seats_max, value: "10")
    create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: seats_sso, value: "true")
    override = create(:entitlement, :contract, organization:, contract:, feature: seats)
    create(:entitlement_value, organization:, entitlement: override, privilege: seats_max, value: "25")
  end

  it "renders the entitlement as it applies to the contract, newest privilege first" do
    expect(payload).to eq(
      lago_contract_id: contract.id,
      feature_code: "seats",
      source: "plan",
      values: [
        {privilege_code: "max", value: 25, plan_value: 10, source: "contract"},
        {privilege_code: "sso", value: true, plan_value: true, source: "plan"}
      ]
    )
  end

  context "with a feature that the catalog plan grants unchanged" do
    let(:contract_entitlement) { contract_entitlements.find { it.code == "storage" } }

    before do
      storage = create(:feature, organization:, code: "storage")
      create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature: storage)
    end

    it "renders the plan as the source" do
      expect(payload).to eq(
        lago_contract_id: contract.id,
        feature_code: "storage",
        source: "plan",
        values: []
      )
    end
  end

  context "with a feature that only the contract grants" do
    let(:contract_entitlement) { contract_entitlements.find { it.code == "storage" } }

    before do
      storage = create(:feature, organization:, code: "storage")
      limit = create(:privilege, organization:, feature: storage, code: "limit", value_type: "integer")
      override = create(:entitlement, :contract, organization:, contract:, feature: storage)
      create(:entitlement_value, organization:, entitlement: override, privilege: limit, value: "10")
    end

    it "renders the contract as the source" do
      expect(payload).to eq(
        lago_contract_id: contract.id,
        feature_code: "storage",
        source: "contract",
        values: [{privilege_code: "limit", value: 10, plan_value: nil, source: "contract"}]
      )
    end
  end
end
