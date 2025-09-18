# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::CustomerResolver do
  let(:query) do
    <<~GQL
      query {
        customerPortalUser {
          id
          name
          currency
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) do
    create(:customer, organization:, currency: "EUR")
  end

  it_behaves_like "requires a customer portal user"

  it "returns a single customer" do
    result = execute_graphql(
      customer_portal_user: customer,
      query:
    )

    customer_response = result["data"]["customerPortalUser"]

    aggregate_failures do
      expect(customer_response["id"]).to eq(customer.id)
      expect(customer_response["name"]).to eq(customer.name)
      expect(customer_response["currency"]).to eq("EUR")
    end
  end

  context "without customer portal user" do
    it "returns an error" do
      result = execute_graphql(
        query:
      )

      expect_unauthorized_error(result)
    end
  end
end
