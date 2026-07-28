# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::IntegrationCustomers::Update do
  let(:required_permission) { "customers:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_customer) do
    create(:netsuite_customer, integration:, customer:, code: "old_code", category: "accounting", is_default: true)
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateIntegrationCustomerInput!) {
        updateIntegrationCustomer(input: $input) {
          ... on NetsuiteCustomer {
            id
            code
            category
            isDefault
            externalCustomerId
            integrationCode
            integrationType
          }
        }
      }
    GQL
  end

  before { integration_customer }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:update"

  it "updates the code of the connection" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {id: integration_customer.id, code: "new_code"}
      }
    )

    data = result["data"]["updateIntegrationCustomer"]

    expect(data["id"]).to eq(integration_customer.id)
    expect(data["code"]).to eq("new_code")
    expect(data["category"]).to eq("accounting")
    expect(data["isDefault"]).to be(true)
    expect(data["integrationCode"]).to eq(integration.code)
    expect(data["integrationType"]).to eq("netsuite")
  end

  it "enqueues the update job when the external customer id is provided" do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: integration_customer.id, externalCustomerId: "external-123", syncWithProvider: true}
        }
      )
    end.to have_enqueued_job(IntegrationCustomers::UpdateJob)
  end

  context "when the integration customer belongs to another organization" do
    let(:integration_customer) { create(:netsuite_customer, code: "old_code") }

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: integration_customer.id, code: "new_code"}
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when the integration customer is not found" do
    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: "unknown", code: "new_code"}
        }
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
