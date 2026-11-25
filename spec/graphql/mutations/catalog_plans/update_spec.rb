# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CatalogPlans::Update do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {input:}
    )
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:required_permission) { "plans:update" }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:input) { {id: catalog_plan.id, name: "Renamed"} }

  let(:query) do
    <<~GQL
      mutation($input: UpdateCatalogPlanInput!) {
        updateCatalogPlan(input: $input) { id name taxes { id code } }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:product_catalog) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  context "when the plan holds rate card attachments" do
    let(:catalog_plan) { create(:catalog_plan, organization:, currency: "EUR") }
    let(:input) { {id: catalog_plan.id, currency: "USD"} }

    before { create(:plan_rate_card, organization:, catalog_plan:) }

    it "reports the frozen currency under the input field name" do
      error = result.dig("errors", 0, "extensions", "details")

      expect(error["currency"]).to eq(["not_editable_with_applied_rate_cards"])
    end
  end

  it "updates the plan" do
    expect(result["data"]["updateCatalogPlan"]["name"]).to eq("Renamed")
    expect(catalog_plan.reload.name).to eq("Renamed")
  end

  context "with metadata" do
    let(:query) do
      <<~GQL
        mutation($input: UpdateCatalogPlanInput!) {
          updateCatalogPlan(input: $input) { id updatedAt metadata { key value } }
        }
      GQL
    end
    let(:input) { {id: catalog_plan.id, metadata:} }
    let(:metadata) { [{key: "tier", value: "gold"}] }
    let(:stored_metadata) { Metadata::ItemMetadata.where(owner: catalog_plan) }
    let(:stored_updated_at) { CatalogPlan.find(catalog_plan.id).updated_at }

    before { create(:item_metadata, owner: catalog_plan, organization:, value: {"crm_id" => "123", "tier" => "silver"}) }

    it "replaces the whole metadata and moves updatedAt" do
      travel_to(1.minute.from_now) { result }

      plan_response = result["data"]["updateCatalogPlan"]
      expect(plan_response["metadata"]).to eq([{"key" => "tier", "value" => "gold"}])
      expect(stored_metadata.sole.value).to eq({"tier" => "gold"})
      expect(Time.zone.parse(plan_response["updatedAt"])).to be > catalog_plan.updated_at
    end

    context "without the argument" do
      let(:input) { {id: catalog_plan.id, name: catalog_plan.name} }

      it "keeps the metadata and updatedAt" do
        travel_to(1.minute.from_now) { result }

        expect(result["data"]["updateCatalogPlan"]["metadata"])
          .to match_array([{"key" => "crm_id", "value" => "123"}, {"key" => "tier", "value" => "silver"}])
        expect(stored_updated_at).to eq(catalog_plan.updated_at)
      end
    end

    context "with an empty list" do
      let(:metadata) { [] }

      it "stores an empty value and returns an empty list" do
        expect(result["data"]["updateCatalogPlan"]["metadata"]).to eq([])
        expect(stored_metadata.sole.value).to eq({})
      end
    end

    context "with null" do
      let(:metadata) { nil }

      it "deletes the metadata" do
        expect(result["errors"]).to be_nil
        expect(result["data"]["updateCatalogPlan"]["metadata"]).to be_nil
        expect(stored_metadata).not_to exist
      end
    end

    context "with a null value" do
      let(:metadata) { [{key: "a", value: nil}] }

      it "round-trips the null value" do
        expect(result["data"]["updateCatalogPlan"]["metadata"]).to eq([{"key" => "a", "value" => nil}])
        expect(stored_metadata.sole.value).to eq({"a" => nil})
      end
    end

    context "with more than 50 keys" do
      let(:metadata) { Array.new(51) { {key: "key_#{it}", value: "v"} } }

      it "returns value_is_invalid and leaves the plan unchanged" do
        travel_to(1.minute.from_now) { result }

        expect(result["errors"].first["extensions"]).to include(
          "status" => 422,
          "code" => "unprocessable_entity",
          "details" => {"metadata" => ["value_is_invalid"]}
        )
        expect(stored_metadata.sole.value).to eq({"crm_id" => "123", "tier" => "silver"})
        expect(stored_updated_at).to eq(catalog_plan.updated_at)
      end
    end

    context "when a key is duplicated" do
      let(:metadata) { [{key: "tier", value: "gold"}, {key: "tier", value: "silver"}] }

      it "returns duplicated_field and writes nothing" do
        expect(result["errors"].first["message"]).to include("duplicated_field")
        expect(stored_metadata.sole.value).to eq({"crm_id" => "123", "tier" => "silver"})
      end
    end
  end

  context "with taxes" do
    let(:tax) { create(:tax, organization:) }
    let(:input) { {id: catalog_plan.id, taxCodes: [tax.code]} }

    it "assigns and returns the taxes" do
      plan_response = result["data"]["updateCatalogPlan"]

      expect(plan_response["taxes"]).to eq([{"id" => tax.id, "code" => tax.code}])
      expect(catalog_plan.reload.taxes).to eq([tax])
    end
  end
end
