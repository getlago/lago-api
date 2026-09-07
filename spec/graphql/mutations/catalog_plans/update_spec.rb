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

  it "updates the plan" do
    expect(result["data"]["updateCatalogPlan"]["name"]).to eq("Renamed")
    expect(catalog_plan.reload.name).to eq("Renamed")
  end
end
