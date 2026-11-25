# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::IntegrationItems::FetchAccounts do
  let(:required_permission) { "organization:integrations:update" }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_item) { create(:integration_item, integration:) }
  let(:sync_service) { instance_double(Integrations::Aggregator::SyncService) }
  let(:accounts_response) do
    File.read(Rails.root.join("spec/fixtures/integration_aggregator/accounts_response.json"))
  end
  let(:mutation) do
    <<~GQL
      mutation($input: FetchIntegrationAccountsInput!) {
        fetchIntegrationAccounts(input: $input) {
          collection { externalName, externalAccountCode, externalId }
        }
      }
    GQL
  end
  let(:account_ids) do
    %w[12ec4c59-ad56-4a4f-93eb-fb0a7740f4e2 6317441d-6547-417c-89e2-6e43ece791d8 80701036-73b5-4468-a4b3-a139262035b4]
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership) { create_default(:membership) }

  before do
    allow(Integrations::Aggregator::SyncService).to receive(:call).and_return(BaseResult.new)

    stub_request(:get, "https://api.nango.dev/records?model=Account&limit=450")
      .to_return(status: 200, body: accounts_response, headers: {})

    integration_item
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "fetches the integration accounts" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {integrationId: integration.id}
      }
    )

    result_data = result["data"]["fetchIntegrationAccounts"]

    ids = result_data["collection"].map { |value| value["externalId"] }

    expect(ids).to eq(account_ids)
    expect(integration.integration_items.where(item_type: :account).count).to eq(3)
  end

  context "with a quickbooks integration" do
    let(:integration) { create(:quickbooks_integration, organization:) }
    let(:active_account) do
      JSON.parse(File.read(Rails.root.join("spec/fixtures/integration_aggregator/quickbooks_accounts_response.json")))["records"].first
    end
    let(:inactive_account) { active_account.merge("id" => "2", "name" => "Inactive", "active" => false) }
    let(:deleted_account) do
      active_account.merge(
        "id" => "3",
        "name" => "Deleted",
        "_nango_metadata" => active_account["_nango_metadata"].merge("deleted_at" => "2026-01-02T00:00:00.000000+00:00")
      )
    end
    let(:accounts_response) { {records: [active_account, inactive_account, deleted_account], next_cursor: nil}.to_json }
    let(:sync_request) do
      stub_request(:post, "https://api.nango.dev/sync/trigger")
        .with(body: hash_including(provider_config_key: "quickbooks", syncs: ["accounts"]))
        .to_return(status: 200, body: "{}")
    end

    before do
      allow(Integrations::Aggregator::SyncService).to receive(:call).and_call_original
      sync_request
    end

    it "stores the active quickbooks accounts from the accounts sync and skips inactive or deleted ones" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {integrationId: integration.id}
        }
      )

      collection = result["data"]["fetchIntegrationAccounts"]["collection"]

      expect(sync_request).to have_been_requested.once
      expect(collection.map { |value| value.slice("externalId", "externalName") })
        .to eq([{"externalId" => "79", "externalName" => "Services"}])
      expect(integration.integration_items.where(item_type: :account).pluck(:external_id, :external_name))
        .to eq([["79", "Services"]])
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
