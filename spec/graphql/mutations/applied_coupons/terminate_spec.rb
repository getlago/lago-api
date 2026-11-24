# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AppliedCoupons::Terminate do
  let(:required_permission) { "coupons:detach" }
  let(:coupon) { create(:coupon, organization:) }
  let(:applied_coupon) { create(:applied_coupon, coupon:, customer:) }
  let(:mutation) do
    <<-GQL
      mutation($input: TerminateAppliedCouponInput!) {
        terminateAppliedCoupon(input: $input) {
          id terminatedAt
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before { applied_coupon }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "coupons:detach"

  it "terminates an applied coupon" do
    result = execute_query(
      query: mutation,
      input: {id: applied_coupon.id}
    )

    data = result["data"]["terminateAppliedCoupon"]

    expect(data["id"]).to eq(applied_coupon.id)
    expect(data["terminatedAt"]).to be_present
  end

  context "when the customer is deleted and activity logs are available" do
    let(:deleted_customer) { create(:customer, organization:) }
    let(:applied_coupon) { create(:applied_coupon, coupon:, customer: deleted_customer) }
    let(:mutation) do
      <<-GQL
        mutation($input: TerminateAppliedCouponInput!) {
          terminateAppliedCoupon(input: $input) {
            id terminatedAt customer { id }
          }
        }
      GQL
    end

    before do
      deleted_customer.discard!
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "terminates the applied coupon and returns its deleted customer" do
      result = execute_query(query: mutation, input: {id: applied_coupon.id})

      expect(result["errors"]).to be_nil
      data = result["data"]["terminateAppliedCoupon"]
      expect(data["id"]).to eq(applied_coupon.id)
      expect(data["customer"]["id"]).to eq(deleted_customer.id)
      expect(applied_coupon.reload).to be_terminated
    end
  end
end
