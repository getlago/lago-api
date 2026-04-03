# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::OrderFormsResolver do
  let(:required_permission) { "order_forms:view" }
  let(:query) {}

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let!(:order_form) { create(:order_form, organization:, customer:, quote:) }
  let!(:signed_order_form) { create(:order_form, :signed, organization:, customer:, quote:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "order_forms:view"

  context "when listing all order forms" do
    let(:query) do
      <<~GQL
        query {
          orderForms(limit: 5) {
            collection {
              id
              number
              status
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns a list of order forms" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(2)
      expect(response["metadata"]["totalCount"]).to eq(2)
    end
  end

  context "when filtering by status" do
    let(:query) do
      <<~GQL
        query($status: [OrderFormStatusEnum!]) {
          orderForms(status: $status, limit: 5) {
            collection { id status }
            metadata { totalCount }
          }
        }
      GQL
    end

    it "returns only matching order forms" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {status: ["generated"]}
      )

      response = result["data"]["orderForms"]

      expect(response["collection"].count).to eq(1)
      expect(response["collection"].first["id"]).to eq(order_form.id)
    end
  end
end
