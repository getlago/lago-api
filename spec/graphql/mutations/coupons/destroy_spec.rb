# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Coupons::Destroy do
  let(:required_permission) { "coupons:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:coupon) { create(:coupon, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyCouponInput!) {
        destroyCoupon(input: $input) { id }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "coupons:delete"

  it "deletes a coupon" do
    result = execute_query(
      query: mutation,
      input: {id: coupon.id}
    )

    data = result["data"]["destroyCoupon"]
    expect(data["id"]).to eq(coupon.id)
  end

  context "when an applied coupon belongs to a deleted customer and activity logs are available" do
    let(:deleted_customer) { create(:customer, organization:) }
    let(:kept_customer) { create(:customer, organization:) }
    let(:deleted_customer_applied_coupon) { create(:applied_coupon, coupon:, customer: deleted_customer) }
    let(:kept_customer_applied_coupon) { create(:applied_coupon, coupon:, customer: kept_customer) }

    before do
      deleted_customer_applied_coupon
      kept_customer_applied_coupon
      deleted_customer.discard!
      allow(Utils::ActivityLog).to receive(:available?).and_return(true)
    end

    it "deletes the coupon and terminates its applied coupons" do
      result = execute_query(query: mutation, input: {id: coupon.id})

      expect(result["errors"]).to be_nil
      expect(result["data"]["destroyCoupon"]["id"]).to eq(coupon.id)
      expect(coupon.reload).to be_discarded
      expect(deleted_customer_applied_coupon.reload).to be_terminated
      expect(kept_customer_applied_coupon.reload).to be_terminated
    end
  end
end
