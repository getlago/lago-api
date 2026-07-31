# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::SelectablePlansResolver do
  let(:required_permission) { "wallets:create" }
  let(:query) do
    <<~GQL
      query {
        selectablePlans(limit: 5) {
          collection { id name code }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", %w[coupons:view coupons:update wallets:create wallets:update]

  it "returns a list of plans with minimal fields" do
    plan = create(:plan, organization:)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    collection = result["data"]["selectablePlans"]["collection"]

    expect(collection.count).to eq(organization.plans.count)
    expect(collection.first["id"]).to eq(plan.id)
    expect(collection.first["name"]).to eq(plan.name)
    expect(collection.first["code"]).to eq(plan.code)

    expect(result["data"]["selectablePlans"]["metadata"]["currentPage"]).to eq(1)
    expect(result["data"]["selectablePlans"]["metadata"]["totalCount"]).to eq(1)
  end
end
