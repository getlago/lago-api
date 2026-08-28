# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::IntegrationCustomers::Create do
  let(:required_permission) { "customers:update" }
  let(:integration) { create(:netsuite_integration, organization:, code: "ns_main") }
  let(:external_customer_id) { SecureRandom.uuid }
  let(:mutation) do
    <<-GQL
      mutation($input: CreateIntegrationCustomerInput!) {
        createIntegrationCustomer(input: $input) {
          ... on NetsuiteCustomer {
            id
            code
            category
            isDefault
            externalCustomerId
            integrationCode
            integrationType
            subsidiaryId
          }
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before { integration }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:update"

  it "creates an integration customer connection" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          integrationId: integration.id,
          code: "netsuite_main",
          externalCustomerId: external_customer_id,
          subsidiaryId: "1"
        }
      }
    )

    data = result["data"]["createIntegrationCustomer"]
    expect(data["id"]).to be_present
    expect(data["code"]).to eq("netsuite_main")
    expect(data["category"]).to eq("accounting")
    expect(data["isDefault"]).to be(true)
    expect(data["externalCustomerId"]).to eq(external_customer_id)
    expect(data["integrationCode"]).to eq("ns_main")
    expect(data["integrationType"]).to eq("netsuite")
    expect(data["subsidiaryId"]).to eq("1")
  end

  context "when the customer already has a default connection in the category" do
    before { create(:xero_customer, customer:, organization:, category: "accounting", code: "xero_main", is_default: true) }

    it "does not mark the new connection as default" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            integrationId: integration.id,
            code: "netsuite_main",
            externalCustomerId: external_customer_id
          }
        }
      )

      expect(result["data"]["createIntegrationCustomer"]["isDefault"]).to be(false)
    end
  end

  context "when neither externalCustomerId nor syncWithProvider is given" do
    it "returns null without an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            integrationId: integration.id,
            code: "netsuite_main"
          }
        }
      )

      expect(result["errors"]).to be_nil
      expect(result["data"]["createIntegrationCustomer"]).to be_nil
    end
  end

  context "when the customer is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: "unknown",
            integrationId: integration.id,
            externalCustomerId: external_customer_id
          }
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when the integration is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            integrationId: "unknown",
            externalCustomerId: external_customer_id
          }
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
