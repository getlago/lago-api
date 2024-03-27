# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AppliedCoupons::Terminate, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization:) }
  let(:applied_coupon) { create(:applied_coupon, coupon:) }

  let(:mutation) do
    <<-GQL
      mutation($input: TerminateAppliedCouponInput!) {
        terminateAppliedCoupon(input: $input) {
          id terminatedAt
        }
      }
    GQL
  end

  before { applied_coupon }

  it "terminates an applied coupon" do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {id: applied_coupon.id}
      }
    )

    data = result["data"]["terminateAppliedCoupon"]

    expect(data["id"]).to eq(applied_coupon.id)
    expect(data["terminatedAt"]).to be_present
  end
end
