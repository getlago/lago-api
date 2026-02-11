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

    it "uses id as external_id for netsuite" do
      result = items_service.call

      expect(result.items.pluck("external_id")).to eq(%w[755 745 753 484 828])
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
              "id" => "799",
              "item_code" => "test-lead-conduit-page-2",
              "name" => "Test-LeadConduit: Page 2",
              "account_code" => "7691"
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

        expect(result.items.pluck("external_id")).to eq(%w[755 745 753 484 828 799])
        expect(IntegrationItem.count).to eq(6)
      end
    end

    context "with a xero integration" do
      let(:integration) { create(:xero_integration) }

      before do
        stub_request(:get, "https://api.nango.dev/v1/xero/items?limit=450")
          .to_return(
            status: 200,
            body: aggregator_response.to_json,
            headers: {"Content-Type" => "application/json"}
          )
      end

      it "uses item_code as external_id for xero" do
        result = items_service.call

        expect(result.items.pluck("external_id")).to eq(
          ["test-lead-conduit", "test-trusted-form", "test-anura", "test-platform", "test-lead-conduit-add-on"]
        )
        expect(IntegrationItem.count).to eq(5)
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
