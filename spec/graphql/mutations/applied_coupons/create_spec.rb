# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::AppliedCoupons::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:mutation) do
    <<-GQL
      mutation($input: CreateAppliedCouponInput!) {
        createAppliedCoupon(input: $input) {
          coupon { id }
          id,
          amountCents,
          amountCurrency,
          createdAt
        }
      }
    GQL
  end

  let(:coupon) { create(:coupon, organization:) }
  let(:customer) { create(:customer, organization:) }

  before do
    create(:subscription, customer:)
  end

  it "assigns a coupon to the customer" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          couponId: coupon.id,
          customerId: customer.id,
          frequency: "once",
          amountCents: 123,
          amountCurrency: "EUR"
        }
      }
    )

    result_data = result["data"]["createAppliedCoupon"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["coupon"]["id"]).to eq(coupon.id)
      expect(result_data["amountCents"]).to eq("123")
      expect(result_data["amountCurrency"]).to eq("EUR")
      expect(result_data["createdAt"]).to be_present
    end
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: {
            couponId: coupon.id,
            customerId: customer.id,
            amountCents: 123,
            amountCurrency: "EUR"
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            couponId: coupon.id,
            customerId: customer.id,
            amountCents: 123,
            amountCurrency: "EUR"
          }
        }
      )

      expect_forbidden_error(result)
    end
  end
end
