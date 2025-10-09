# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Coupons::Terminate do
  let(:required_permission) { "coupons:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: TerminateCouponInput!) {
        terminateCoupon(input: $input) {
          id name status terminatedAt
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", "coupons:update"

  it "terminates a coupon" do
    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: coupon.id}
      }
    )

    data = result["data"]["terminateCoupon"]
    expect(data["id"]).to eq(coupon.id)
    expect(data["name"]).to eq(coupon.name)
    expect(data["status"]).to eq("terminated")
    expect(data["terminatedAt"]).to be_present
  end
end
