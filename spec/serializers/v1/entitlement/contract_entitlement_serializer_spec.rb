# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::Entitlement::ContractEntitlementSerializer do
  subject(:serializer) do
    ::CollectionSerializer.new(
      Entitlement::SubscriptionEntitlement.for_contract(contract),
      described_class,
      collection_name: "entitlements"
    )
  end

  let_it_be(:organization) { create_default(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, catalog_plan:) }
  let(:feature) { create(:feature, organization:, code: "seats", name: "Seats", description: "Users") }
  let(:max) { create(:privilege, organization:, feature:, code: "max", name: "Max", value_type: "integer") }
  let(:reset) { create(:privilege, organization:, feature:, code: "reset", name: nil, value_type: "string") }
  let(:plan_entitlement) { create(:entitlement, :catalog_plan, organization:, catalog_plan:, feature:, created_at: 2.days.ago) }
  let(:contract_entitlement) { create(:entitlement, :contract, organization:, contract:, feature:) }

  before do
    create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: max, value: 50, created_at: 2.days.ago)
    create(:entitlement_value, organization:, entitlement: plan_entitlement, privilege: reset, value: "email", created_at: 1.day.ago)
    create(:entitlement_value, organization:, entitlement: contract_entitlement, privilege: max, value: 80)
  end

  it "renders the contract entitlements in the v1 subscription shape" do
    expect(serializer.serialize).to eq(
      entitlements: [
        {
          code: "seats",
          name: "Seats",
          description: "Users",
          privileges: [
            {code: "max", name: "Max", value_type: "integer", value: 80, plan_value: 50, override_value: 80, config: {}},
            {code: "reset", name: nil, value_type: "string", value: "email", plan_value: "email", override_value: nil, config: {}}
          ],
          overrides: {"max" => 80}
        }
      ]
    )
  end
end
