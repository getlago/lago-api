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
    before { allow(CatalogPlans::UpdateService).to receive(:call).and_call_original }

    [
      ["pairs", [{key: "tier", value: "gold"}, {key: "note", value: nil}], {"tier" => "gold", "note" => nil}],
      ["an empty list", [], {}],
      ["null", nil, nil]
    ].each do |description, metadata, expected|
      context "with #{description}" do
        let(:input) { {id: catalog_plan.id, metadata:} }

        it "passes the metadata to the update service as a hash" do
          result

          expect(CatalogPlans::UpdateService).to have_received(:call)
            .with(catalog_plan:, params: {metadata: expected})
        end
      end
    end

    context "without the argument" do
      it "passes no metadata to the update service" do
        result

        expect(CatalogPlans::UpdateService).to have_received(:call).with(catalog_plan:, params: {name: "Renamed"})
      end
    end

    context "when a key is duplicated" do
      let(:input) { {id: catalog_plan.id, metadata: [{key: "tier", value: "gold"}, {key: "tier", value: "silver"}]} }

      it "returns duplicated_field without calling the update service" do
        expect(result["errors"].first["message"]).to include("duplicated_field")
        expect(CatalogPlans::UpdateService).not_to have_received(:call)
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
