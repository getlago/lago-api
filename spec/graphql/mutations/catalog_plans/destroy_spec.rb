# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CatalogPlans::Destroy do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {input: {id: catalog_plan.id}}
    )
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:required_permission) { "plans:delete" }
  let(:catalog_plan) { create(:catalog_plan, organization:) }

  let(:query) do
    <<~GQL
      mutation($input: DestroyCatalogPlanInput!) {
        destroyCatalogPlan(input: $input) { id }
      }
    GQL
  end

  before { organization.enable_feature_flag!(:product_catalog) }

  it_behaves_like "requires permission", "plans:delete"

  it "soft deletes the catalog plan" do
    expect { result }.to change { catalog_plan.reload.discarded? }.from(false).to(true)
    expect(result["data"]["destroyCatalogPlan"]["id"]).to eq(catalog_plan.id)
  end

  context "when the plan is attached to contracts" do
    before { create(:contract, organization:, catalog_plan:) }

    it "returns a validation error" do
      expect(result["errors"].first.dig("extensions", "code")).to eq("unprocessable_entity")
      expect(catalog_plan.reload).not_to be_discarded
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(result["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
