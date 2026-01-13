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
      allow(LagoHttpClient::Client).to receive(:new)
        .with(items_endpoint, retries_on: [OpenSSL::SSL::SSLError])
        .and_return(lago_client)
      allow(lago_client).to receive(:get)
        .with(headers:, params:)
        .and_return(aggregator_response)

      IntegrationItem.destroy_all
    end

    it "successfully fetches items" do
      result = items_service.call

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new).with(items_endpoint, retries_on: [OpenSSL::SSL::SSLError])
        expect(lago_client).to have_received(:get)
        expect(result.items.pluck("external_id")).to eq(%w[755 745 753 484 828])
        expect(IntegrationItem.count).to eq(5)
      end
    end

    context "with item_code in response" do
      let(:aggregator_response) do
        {
          "next_cursor" => nil,
          "records" => [
            {
              "id" => "ceddd893-05b9-48ae-b3f2-29c504aff6b6",
              "item_code" => "seats",
              "name" => "Seat",
              "description" => "Seat",
              "account_code" => "4100",
              "_nango_metadata" => {
                "first_seen_at" => "2025-12-30T20:27:21.012989+00:00",
                "last_modified_at" => "2025-12-30T20:27:21.012989+00:00",
                "last_action" => "ADDED",
                "deleted_at" => nil,
                "pruned_at" => nil,
                "cursor" => "MjAyNS0xMi0zMLThiNDdhMGM5YjliYQ=="
              }
            }
          ]
        }
      end

      it "saves item_code on integration items" do
        result = items_service.call

        expect(result.items.sole.item_code).to eq "seats"
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

  describe "#params" do
    subject(:params_call) { items_service.__send__(:params) }

    context "when cursor is not present" do
      let(:params) { {limit: 450} }

      it "returns the params" do
        expect(subject).to eq(params)
      end
    end

    context "when cursor is present" do
      let(:params) { {limit: 450, cursor:} }
      let(:cursor) { "cursor" }

      before do
        items_service.instance_variable_set(:@cursor, cursor)
      end

      it "returns the params with cursor" do
        expect(subject).to eq(params)
      end
    end
  end
end
