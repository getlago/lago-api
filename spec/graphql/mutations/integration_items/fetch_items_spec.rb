# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::IntegrationItems::FetchItems do
  let(:required_permission) { "organization:integrations:update" }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_item) { create(:integration_item, integration:) }
  let(:sync_service) { instance_double(Integrations::Aggregator::SyncService) }
  let(:items_response) do
    File.read(Rails.root.join("spec/fixtures/integration_aggregator/items_response.json"))
  end
  let(:mutation) do
    <<~GQL
      mutation($input: FetchIntegrationItemsInput!) {
        fetchIntegrationItems(input: $input) {
          collection { externalName, externalAccountCode, externalId }
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership) { create_default(:membership) }

  before do
    allow(Integrations::Aggregator::SyncService).to receive(:call).and_return(true)

    stub_request(:get, "https://api.nango.dev/records?model=Item&limit=450")
      .to_return(status: 200, body: items_response, headers: {})

    integration_item
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "fetches the integration items" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {integrationId: integration.id}
      }
    )

    result_data = result["data"]["fetchIntegrationItems"]

    external_ids = result_data["collection"].map { |value| value["externalId"] }

    expect(external_ids).to eq(%w[755 745 753 484 828])
    expect(integration.integration_items.where(item_type: :standard).count).to eq(5)
  end

  context "with a quickbooks integration" do
    let(:integration) { create(:quickbooks_integration, organization:) }
    let(:active_item) do
      JSON.parse(File.read(Rails.root.join("spec/fixtures/integration_aggregator/quickbooks_items_response.json")))["records"].first
    end
    let(:inactive_item) { active_item.merge("id" => "2", "name" => "Inactive", "active" => false) }
    let(:deleted_item) do
      active_item.merge(
        "id" => "3",
        "name" => "Deleted",
        "_nango_metadata" => active_item["_nango_metadata"].merge("deleted_at" => "2026-01-02T00:00:00.000000+00:00")
      )
    end
    let(:items_response) { {records: [active_item, inactive_item, deleted_item], next_cursor: nil}.to_json }
    let(:sync_request) do
      stub_request(:post, "https://api.nango.dev/sync/trigger")
        .with(body: hash_including(provider_config_key: "quickbooks", syncs: ["items"]))
        .to_return(status: 200, body: "{}")
    end

    before do
      allow(Integrations::Aggregator::SyncService).to receive(:call).and_call_original
      sync_request
    end

    it "stores the active quickbooks items from the items sync and skips inactive or deleted ones" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {integrationId: integration.id}
        }
      )

      collection = result["data"]["fetchIntegrationItems"]["collection"]

      expect(sync_request).to have_been_requested.once
      expect(collection.map { |value| value.slice("externalId", "externalName") })
        .to eq([{"externalId" => "1", "externalName" => "Consulting"}])
      expect(integration.integration_items.where(item_type: :standard).pluck(:external_id, :external_name))
        .to eq([["1", "Consulting"]])
    end

    context "when the integration is flagged with a realm id mismatch" do
      let(:integration) do
        create(:quickbooks_integration, organization:, settings: {realm_id: "1234567890", sandbox: false, realm_id_mismatch: true})
      end

      it "returns realm_id_changed without any request to Nango and keeps the stored items" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query: mutation,
          variables: {
            input: {integrationId: integration.id}
          }
        )

        expect(result["data"]).to be_nil
        expect(result["errors"].sole).to include(
          "message" => "forbidden",
          "extensions" => {"status" => 403, "code" => "realm_id_changed"}
        )
        expect(sync_request).not_to have_been_requested
        expect(a_request(:get, %r{api.nango.dev/records})).not_to have_been_made
        expect(integration.integration_items.reload).to eq([integration_item])
      end
    end
  end
end
