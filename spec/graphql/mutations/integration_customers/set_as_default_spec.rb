# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::IntegrationCustomers::SetAsDefault do
  let(:required_permission) { "customers:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:user) { membership.user }

  let(:netsuite_customer) do
    create(:netsuite_customer, customer:, organization:, category: "accounting", code: "netsuite_eu", is_default: true)
  end
  let(:xero_customer) do
    create(:xero_customer, customer:, organization:, category: "accounting", code: "xero_eu", is_default: false)
  end

  let(:mutation) do
    <<-GQL
      mutation($input: SetIntegrationCustomerAsDefaultInput!) {
        setIntegrationCustomerAsDefault(input: $input) {
          ... on XeroCustomer {
            id
            isDefault
          }
        }
      }
    GQL
  end

  before do
    netsuite_customer
    xero_customer
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:update"

  context "with valid preconditions" do
    it "sets the connection as default and returns the connection" do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {customerId: customer.id, code: "xero_eu"}
        }
      )

      data = result["data"]["setIntegrationCustomerAsDefault"]

      expect(data["id"]).to eq(xero_customer.id)
      expect(data["isDefault"]).to be(true)
      expect(xero_customer.reload.is_default).to be(true)
      expect(netsuite_customer.reload.is_default).to be(false)
    end
  end

  context "when the connection is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {customerId: customer.id, code: "unknown"}
        }
      )

      expect_not_found(result)
    end
  end
end
