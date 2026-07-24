# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::IntegrationCustomers::Destroy do
  let(:required_permission) { "customers:update" }
  let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyIntegrationCustomerInput!) {
        destroyIntegrationCustomer(input: $input) { id }
      }
    GQL
  end

  before { integration_customer }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "customers:update"

  it "deletes an integration customer" do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: integration_customer.id}
        }
      )
    end.to change(::IntegrationCustomers::BaseCustomer, :count).by(-1)
  end

  context "when integration customer is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {id: "123456"}
        }
      )

      expect_not_found(result)
    end
  end
end
