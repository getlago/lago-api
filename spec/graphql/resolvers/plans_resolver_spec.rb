# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PlansResolver do
  let(:required_permission) { "plans:view" }
  let(:query) do
    <<~GQL
      query($withDeleted: Boolean) {
        plans(limit: 5, withDeleted: $withDeleted) {
          collection { id chargesCount customersCount }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:plan) { create(:plan, organization:) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  before do
    plan
    customer

    2.times do
      create(:subscription, customer:, plan:)
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:view"

  it "returns a list of plans" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    plans_response = result["data"]["plans"]

    expect(plans_response["collection"].count).to eq(organization.plans.count)
    expect(plans_response["collection"].first["id"]).to eq(plan.id)
    expect(plans_response["collection"].first["customersCount"]).to eq(1)

    expect(plans_response["metadata"]["currentPage"]).to eq(1)
    expect(plans_response["metadata"]["totalCount"]).to eq(1)
  end

  context "when filtering by with_deleted" do
    let(:plan) { create(:plan, organization:) }
    let(:deleted_plan) { create(:plan, organization:, deleted_at: Time.current) }

    before do
      plan
      deleted_plan
    end

    it "returns all plans including deleted ones" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {withDeleted: true}
      )

      plans_response = result["data"]["plans"]
      expect(plans_response["collection"].count).to eq(2)
      expect(plans_response["collection"].map { |p| p["id"] }).to include(plan.id, deleted_plan.id)

      expect(plans_response["metadata"]["currentPage"]).to eq(1)
      expect(plans_response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "when filtering by product_category_id" do
    let(:product_category) { create(:product_category, organization:) }
    let(:other_plan) { create(:plan, organization:) }
    let(:query) do
      <<~GQL
        query($productCategoryId: ID!) {
          plans(limit: 5, productCategoryId: $productCategoryId) {
            collection { id }
            metadata { totalCount }
          }
        }
      GQL
    end

    before do
      other_plan
      item = create(:product, organization:, product_category:)
      rate_card = create(:rate_card, organization:, product: item)
      create(:plan_rate_card, organization:, plan:, rate_card:)
    end

    it "returns only the plans linked to the product_category" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {productCategoryId: product_category.id}
      )

      plans_response = result["data"]["plans"]
      expect(plans_response["collection"].map { |p| p["id"] }).to eq([plan.id])
      expect(plans_response["metadata"]["totalCount"]).to eq(1)
    end
  end
end
