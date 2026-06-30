# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PlanProductItems::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {planId: plan.id, productItemId: product_item.id, rateCardId: rate_card.id, units: 10.0}}
    )
  end

  let(:required_permission) { "plans:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:product_item) { create(:product_item, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product_item:) }

  let(:mutation) do
    <<~GQL
      mutation($input: CreatePlanProductItemInput!) {
        createPlanProductItem(input: $input) {
          id
          units
          ratePhasesCount
          productItem { id }
          rateCard { id }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  it "assigns the product item to the plan with a default rate phase" do
    response = execution["data"]["createPlanProductItem"]

    expect(response["productItem"]["id"]).to eq(product_item.id)
    expect(response["rateCard"]["id"]).to eq(rate_card.id)
    expect(response["units"]).to eq(10.0)
    expect(response["ratePhasesCount"]).to eq(1)
  end
end
