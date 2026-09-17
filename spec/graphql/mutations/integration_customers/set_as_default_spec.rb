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

  let(:anrok_customer) do
    create(:anrok_customer, customer:, organization:, category: "tax", code: "xero_eu", is_default: true)
  end

  let(:mutation) do
    <<-GQL
      mutation($input: SetIntegrationCustomerAsDefaultInput!) {
        setIntegrationCustomerAsDefault(input: $input) {
          ... on XeroCustomer {
            id
            category
            code
            isDefault
          }
        }
      }
    GQL
  end

  before do
    netsuite_customer
    xero_customer
    anrok_customer
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
          input: {id: xero_customer.id}
        }
      )

      data = result["data"]["setIntegrationCustomerAsDefault"]

      expect(data["id"]).to eq(xero_customer.id)
      expect(data["category"]).to eq("accounting")
      expect(data["code"]).to eq("xero_eu")
      expect(data["isDefault"]).to be(true)
      expect(xero_customer.reload.is_default).to be(true)
      expect(netsuite_customer.reload.is_default).to be(false)
    end

    it "only clears defaults within the connection's own category" do
      execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: xero_customer.id}
        }
      )

      expect(xero_customer.reload.is_default).to be(true)
      expect(anrok_customer.reload.is_default).to be(true)
    end
  end

  context "when the connection belongs to another organization" do
    let(:other_customer) { create(:customer) }
    let(:other_connection) do
      create(:xero_customer, customer: other_customer, organization: other_customer.organization, category: "accounting", code: "xero_eu")
    end

    it "returns an error" do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: other_connection.id}
        }
      )

      expect_not_found(result)
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
          input: {id: SecureRandom.uuid}
        }
      )

      expect_not_found(result)
    end
  end
end
