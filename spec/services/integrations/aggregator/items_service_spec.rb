# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::ItemsService do
  subject(:items_service) { described_class.new(integration:) }

  let(:integration) { create(:netsuite_integration) }

  describe ".call" do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:items_endpoint) { "https://api.nango.dev/v1/netsuite/items" }
    let(:params) { {limit: 450} }

    let(:headers) do
      {
        "Connection-Id" => integration.connection_id,
        "Authorization" => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
        "Provider-Config-Key" => "netsuite-tba"
      }
    end

    let(:aggregator_response) do
      path = Rails.root.join("spec/fixtures/integration_aggregator/items_response.json")
      JSON.parse(File.read(path))
    end

    before do
      stub_request(:get, "https://api.nango.dev/v1/netsuite/items?limit=450")
        .to_return(
          status: 200,
          body: aggregator_response.to_json,
          headers: {"Content-Type" => "application/json"}
        )

      IntegrationItem.destroy_all
    end

    it "successfully fetches items" do
      result = items_service.call

      expect(result.items.pluck("external_id")).to eq(["test-lead-conduit", "test-trusted-form", "test-anura", "test-platform", "test-lead-conduit-add-on"])
      expect(IntegrationItem.count).to eq(5)
    end

    context "when cursor is present" do
      let(:aggregator_response) do
        super().merge("next_cursor" => "abc123")
      end

      before do
        second_page_response = {
          "records" => [
            {
              id: "799",
              item_code: "test-lead-conduit-page-2",
              name: "Test-LeadConduit: Page 2",
              account_code: "7691",
              _nango_metadata: {
                first_seen_at: "2024-04-17T12:10:02.430428+00:00",
                last_modified_at: "2024-04-17T12:10:02.430428+00:00",
                last_action: "ADDED",
                deleted_at: nil,
                cursor: "MjAyNC0wNC0xN1QxMjoxMDowMi40MzA0MjgrMDA6MDB8fDAwNmZmYjJjLWQ1MjAtNWNiNy1hMjRhLTE5NzYzNzI1MDhlZQ=="
              }
            }
          ]
        }
        stub_request(:get, "https://api.nango.dev/v1/netsuite/items?limit=450&cursor=abc123")
          .to_return(
            status: 200,
            body: second_page_response.to_json,
            headers: {"Content-Type" => "application/json"}
          )
      end

      it "makes subsequent requests until cursor is nil" do
        result = items_service.call

        expect(result.items.pluck("external_id")).to eq(["test-lead-conduit", "test-trusted-form", "test-anura", "test-platform", "test-lead-conduit-add-on", "test-lead-conduit-page-2"])
        expect(IntegrationItem.count).to eq(6)
      end
    end
  end

  describe "#action_path" do
    subject(:action_path_call) { items_service.action_path }

    let(:action_path) { "v1/netsuite/items" }

    it "returns the path" do
      expect(subject).to eq(action_path)
    end
  end
end
