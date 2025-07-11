# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Entitlement::UpdatePlanEntitlements, type: :graphql do
  subject { execute_query(query:, input:) }

  let(:required_permission) { "plans:update" }
  let(:organization) { create(:organization) }

  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:plan) { create(:plan, organization:) }
  let(:privilege) { create(:privilege, feature:, code: "max") }

  let(:query) do
    <<~GQL
      mutation($input: UpdatePlanEntitlementsInput!) {
        updatePlanEntitlements(input: $input) {
          collection {
            code
            name
            description
            privileges { code name value valueType config }
          }
        }
      }
    GQL
  end

  let(:input) do
    {
      planId: plan.id,
      entitlements: [
        {featureCode: feature.code}
      ]
    }
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"
  it_behaves_like "requires Premium license"

  it "updates a feature" do
    result = subject

    result_data = result["data"]["updatePlanEntitlements"]["collection"]
    expect(result_data.sole).to match({
      "code" => "seats",
      "name" => String,
      "description" => String,
      "privileges" => []
    })
  end

  context "when feature does not exist" do
    let(:input) do
      {
        planId: plan.id,
        entitlements: [
          {featureCode: "not_existing"}
        ]
      }
    end

    it "returns not found error" do
      expect_graphql_error(result: subject, message: "not_found")
    end
  end

  context "with privileges" do
    context "when privilege already exists" do
      let(:input) do
        {
          planId: plan.id,
          entitlements: [
            {featureCode: feature.code, privileges: [
              {privilegeCode: privilege.code, value: "100"}
            ]}
          ]
        }
      end

      it "updates the privilege" do
        result = subject

        result_data = result["data"]["updatePlanEntitlements"]["collection"]
        expect(result_data.sole["privileges"].sole).to eq({
          "code" => "max",
          "name" => nil,
          "value" => "100",
          "valueType" => "string",
          "config" => {}
        })
      end
    end

    context "when privilege is not found" do
      let(:input) do
        {
          planId: plan.id,
          entitlements: [
            {featureCode: feature.code, privileges: [
              {privilegeCode: "not_existing", value: "100"}
            ]}
          ]
        }
      end

      it "returns not found error" do
        expect_graphql_error(result: subject, message: "not_found")
      end
    end
  end

  context "when there are existing entitlements" do
    let(:input) do
      {
        planId: plan.id,
        entitlements: [
          {featureCode: "seats", privileges: [
            {privilegeCode: "max", value: "100"}
          ]}
        ]
      }
    end

    it "remove missing privilege and features" do
      feature
      privilege
      existing_seat_privilege = create(:privilege, feature:, code: "root?", value_type: "boolean")
      ent = create(:entitlement, plan:, feature:)
      root_value = create(:entitlement_value, entitlement: ent, privilege: existing_seat_privilege, value: "true")
      existing_feature = create(:feature, code: "salesforce")
      salesforce_ent = create(:entitlement, plan:, feature: existing_feature)

      result = subject

      result_data = result["data"]["updatePlanEntitlements"]["collection"]
      expect(result_data.sole["code"]).to eq "seats"
      expect(result_data.sole["privileges"].sole).to eq({
        "code" => "max",
        "name" => nil,
        "value" => "100",
        "valueType" => "string",
        "config" => {}
      })
      expect(salesforce_ent.reload).to be_discarded
      expect(root_value.reload).to be_discarded
    end
  end

  context "when plan does not exist" do
    let(:input) do
      {
        planId: "non-existent-id",
        entitlements: []
      }
    end

    it "returns not found error" do
      pps subject
      expect_graphql_error(result: subject, message: "not_found")
    end
  end
end
