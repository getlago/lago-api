# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CatalogPlans::Create do
  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {input:}
    )
  end

  let_it_be(:membership, refind: true) { create_default(:membership) }
  let(:organization) { membership.organization }
  let(:required_permission) { "plans:create" }
  let(:input) { {name: "Growth", code: "growth", currency: "EUR"} }

  let(:query) do
    <<~GQL
      mutation($input: CreateCatalogPlanInput!) {
        createCatalogPlan(input: $input) { id code currency taxes { id code } }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:product_catalog) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:create"

  it "creates a catalog plan" do
    plan_response = result["data"]["createCatalogPlan"]

    expect(plan_response["code"]).to eq("growth")
    expect(plan_response["currency"]).to eq("EUR")
    expect(CatalogPlan.find(plan_response["id"])).to have_attributes(name: "Growth", currency: "EUR")
  end

  context "with taxes" do
    let(:tax) { create(:tax, organization:) }
    let(:input) { {name: "Growth", code: "growth", currency: "EUR", taxCodes: [tax.code]} }

    it "assigns and returns the taxes" do
      plan_response = result["data"]["createCatalogPlan"]

      expect(plan_response["taxes"]).to eq([{"id" => tax.id, "code" => tax.code}])
      expect(CatalogPlan.find(plan_response["id"]).taxes).to eq([tax])
    end
  end

  context "with metadata" do
    let(:query) do
      <<~GQL
        mutation($input: CreateCatalogPlanInput!) {
          createCatalogPlan(input: $input) { id metadata { key value } }
        }
      GQL
    end
    let(:input) { {name: "Growth", code: "growth", currency: "EUR", metadata:} }
    let(:metadata) { [{key: "crm_id", value: "123"}, {key: "tier", value: nil}] }

    it "stores and returns the pairs" do
      plan_response = result["data"]["createCatalogPlan"]

      expect(plan_response["metadata"]).to match_array([{"key" => "crm_id", "value" => "123"}, {"key" => "tier", "value" => nil}])
      expect(Metadata::ItemMetadata.find_by(owner_type: "CatalogPlan", owner_id: plan_response["id"]).value)
        .to eq({"crm_id" => "123", "tier" => nil})
    end

    context "when a key is duplicated" do
      let(:metadata) { [{key: "tier", value: "gold"}, {key: "tier", value: "silver"}] }

      it "returns duplicated_field and writes nothing" do
        expect(result["errors"].first["message"]).to include("duplicated_field")
        expect(CatalogPlan.where(code: "growth")).not_to exist
        expect(Metadata::ItemMetadata.where(owner_type: "CatalogPlan")).not_to exist
      end
    end

    context "when metadata is an empty list" do
      let(:metadata) { [] }

      it "stores an empty value and returns an empty list" do
        plan_response = result["data"]["createCatalogPlan"]

        expect(plan_response["metadata"]).to eq([])
        expect(Metadata::ItemMetadata.find_by(owner_type: "CatalogPlan", owner_id: plan_response["id"]).value).to eq({})
      end
    end

    context "when metadata is null" do
      let(:metadata) { nil }

      it "creates the plan without metadata" do
        plan_response = result["data"]["createCatalogPlan"]

        expect(plan_response["metadata"]).to be_nil
        expect(Metadata::ItemMetadata.where(owner_type: "CatalogPlan")).not_to exist
      end
    end

    [
      ["more than 50 keys", Array.new(51) { {key: "key_#{it}", value: "v"} }],
      ["a key longer than 100 characters", [{key: "k" * 101, value: "v"}]],
      ["a value longer than 255 characters", [{key: "k", value: "v" * 256}]]
    ].each do |description, invalid_metadata|
      context "with #{description}" do
        let(:metadata) { invalid_metadata }

        it "returns value_is_invalid and creates no plan" do
          expect(result["errors"].first["extensions"]).to include(
            "status" => 422,
            "code" => "unprocessable_entity",
            "details" => {"metadata" => ["value_is_invalid"]}
          )
          expect(CatalogPlan.where(code: "growth")).not_to exist
        end
      end
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(result["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
