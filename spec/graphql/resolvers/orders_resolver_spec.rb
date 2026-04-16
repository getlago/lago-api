# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::OrdersResolver do
  let(:required_permission) { "orders:view" }
  let(:query) {}

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote:) }
  let(:order_form_two) { create(:order_form, :signed, organization:, customer:, quote:) }
  let!(:order_two) { create(:order, organization:, customer:, order_form: order_form_two, order_type: :one_off) }

  before { create(:order, organization:, customer:, order_form:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "orders:view"

  context "when listing all orders" do
    let(:query) do
      <<~GQL
        query {
          orders(limit: 5) {
            collection {
              id
              number
              status
              orderType
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns a list of orders" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result["data"]["orders"]

      expect(response["collection"].count).to eq(2)
      expect(response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "when filtering by order type" do
    let(:query) do
      <<~GQL
        query($orderType: [OrderTypeEnum!]) {
          orders(orderType: $orderType, limit: 5) {
            collection { id orderType }
            metadata { totalCount }
          }
        }
      GQL
    end

    it "returns only matching orders" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {orderType: ["one_off"]}
      )

      response = result["data"]["orders"]

      expect(response["collection"].count).to eq(1)
      expect(response["collection"].first["id"]).to eq(order_two.id)
    end
  end
end
