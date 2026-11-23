# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::IntegrationItems::FetchCustomers do
  let(:required_permission) { "organization:integrations:update" }
  let(:organization) { membership.organization }
  let(:integration) { create(:quickbooks_integration, organization:) }
  let(:mutation) do
    <<~GQL
      mutation($input: FetchIntegrationCustomersInput!) {
        fetchIntegrationCustomers(input: $input) {
          collection { itemType, externalName, externalAccountCode, externalId }
        }
      }
    GQL
  end
  let(:active_customer) do
    JSON.parse(File.read(Rails.root.join("spec/fixtures/integration_aggregator/quickbooks_customers_response.json")))["records"].first
  end
  let(:inactive_customer) { active_customer.merge("id" => "90", "display_name" => "Inactive", "active" => false) }
  let(:deleted_customer) do
    active_customer.merge(
      "id" => "91",
      "display_name" => "Deleted",
      "_nango_metadata" => active_customer["_nango_metadata"].merge("deleted_at" => "2026-01-02T00:00:00.000000+00:00")
    )
  end
  let(:customers_response) { {records: [active_customer, inactive_customer, deleted_customer], next_cursor: nil}.to_json }
  let(:sync_request) do
    stub_request(:post, "https://api.nango.dev/sync/trigger")
      .with(body: hash_including(provider_config_key: "quickbooks", syncs: ["customers"]))
      .to_return(status: 200, body: "{}")
  end
  let(:records_request) do
    stub_request(:get, "https://api.nango.dev/records?model=Customer&limit=450")
      .to_return(status: 200, body: customers_response, headers: {})
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership) { create_default(:membership) }

  before do
    sync_request
    records_request
  end

  def fetch_customers
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {integrationId: integration.id}
      }
    )
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "stores the active quickbooks customers from the customers sync and skips inactive or deleted ones" do
    result = fetch_customers

    collection = result["data"]["fetchIntegrationCustomers"]["collection"]

    expect(sync_request).to have_been_requested.once
    expect(records_request).to have_been_requested.once
    expect(collection).to eq(
      [{"itemType" => "customer", "externalId" => "58", "externalName" => "Northwind Analytics", "externalAccountCode" => nil}]
    )
    expect(integration.integration_items.where(item_type: :customer).pluck(:external_id, :external_name))
      .to eq([["58", "Northwind Analytics"]])
  end

  it "replaces only the customer items of the integration" do
    standard_item = create(:integration_item, integration:, item_type: :standard)
    account_item = create(:integration_item, integration:, item_type: :account)
    stale_customer = create(:integration_item, integration:, item_type: :customer, external_id: "1", external_name: "Stale")
    other_integration = create(:netsuite_integration, organization:)
    other_customer = create(:integration_item, integration: other_integration, item_type: :customer)

    fetch_customers

    expect(IntegrationItem.where(id: stale_customer.id)).not_to exist
    expect(integration.integration_items.where(item_type: :customer).pluck(:external_id)).to eq(["58"])
    expect(integration.integration_items.where(id: [standard_item.id, account_item.id]).count).to eq(2)
    expect(other_customer.reload).to be_persisted
  end

  context "when the customers service fails" do
    before do
      allow(Integrations::Aggregator::CustomersService).to receive(:call).with(integration:).and_return(
        Integrations::Aggregator::CustomersService::Result.new.tap do |result|
          result.service_failure!(code: "action_script_runtime_error", message: "boom")
        end
      )
    end

    it "returns the service error" do
      result = fetch_customers

      expect(result["data"]).to be_nil
      expect_graphql_error(result:, message: "action_script_runtime_error")
    end
  end
end
