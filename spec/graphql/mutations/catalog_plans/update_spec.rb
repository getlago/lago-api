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
  let(:plan) { create(:plan, :product_catalog, organization:) }
  let(:input) { {id: plan.id, name: "Renamed"} }

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
    let(:input) { {id: plan.id, currency: "USD"} }

    before do
      product = create(:product, organization:)
      rate_card = create(:rate_card, organization:, product:, currency: plan.amount_currency)
      plan.applied_rate_cards.create!(organization:, rate_card:, units: 1)
    end

    it "reports the frozen currency under the input field name" do
      error = result.dig("errors", 0, "extensions", "details")

      expect(error["currency"]).to eq(["not_editable_with_applied_rate_cards"])
      expect(error).not_to have_key("amountCurrency")
    end
  end

  it "updates the plan" do
    expect(result["data"]["updateCatalogPlan"]["name"]).to eq("Renamed")
    expect(plan.reload.name).to eq("Renamed")
  end
end
