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
        updateCatalogPlan(input: $input) { id name }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:product_catalog) }

  it_behaves_like "requires permission", "plans:update"

  context "when the plan holds rate card attachments" do
    let(:catalog_plan) { create(:catalog_plan, organization:, currency: "EUR") }
    let(:input) { {id: catalog_plan.id, currency: "USD"} }

    before { create(:plan_rate_card, organization:, catalog_plan:) }

    it "reports the frozen currency under the input field name" do
      error = result.dig("errors", 0, "extensions", "details")

      expect(error["currency"]).to eq(["not_editable_with_applied_rate_cards"])
      expect(error).not_to have_key("amountCurrency")
    end
  end

  it "updates the plan" do
    expect(result["data"]["updateCatalogPlan"]["name"]).to eq("Renamed")
    expect(catalog_plan.reload.name).to eq("Renamed")
  end
end
