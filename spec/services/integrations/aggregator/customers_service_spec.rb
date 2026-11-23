# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::CustomersService do
  subject(:customers_service) { described_class.new(integration:) }

  before_all do
    create_default(:organization)
  end

  let(:integration) { create(:quickbooks_integration) }

  describe ".call" do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:customers_endpoint) { "https://api.nango.dev/records" }
    let(:params) { {model: "Customer", limit: 450} }

    let(:headers) do
      {
        "Connection-Id" => "quickbooks-test-connection",
        "Authorization" => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
        "Provider-Config-Key" => "quickbooks"
      }
    end

    let(:aggregator_response) do
      path = Rails.root.join("spec/fixtures/integration_aggregator/quickbooks_customers_response.json")
      JSON.parse(File.read(path))
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(customers_endpoint, retries_on: [OpenSSL::SSL::SSLError])
        .and_return(lago_client)
      allow(lago_client).to receive(:get)
        .with(headers:, params:)
        .and_return(aggregator_response)
    end

    it "stores the customer records with their id and display name" do
      result = customers_service.call

      expect(lago_client).to have_received(:get).with(headers:, params:).once
      expect(result.customers.map { |customer| [customer.external_id, customer.external_name] })
        .to eq([["58", "Northwind Analytics"], ["59", "Acme Robotics"]])
      expect(integration.integration_items.pluck(:item_type, :external_id, :external_name, :external_account_code))
        .to contain_exactly(
          ["customer", "58", "Northwind Analytics", nil],
          ["customer", "59", "Acme Robotics", nil]
        )
    end

    context "with inactive or deleted records" do
      let(:active_customer) { aggregator_response["records"].first }
      let(:inactive_customer) { active_customer.merge("id" => "60", "display_name" => "Inactive", "active" => false) }
      let(:deleted_customer) do
        active_customer.merge(
          "id" => "61",
          "display_name" => "Deleted",
          "_nango_metadata" => active_customer["_nango_metadata"].merge("deleted_at" => "2026-01-02T00:00:00.000000+00:00")
        )
      end

      before do
        allow(lago_client).to receive(:get)
          .with(headers:, params:)
          .and_return({"records" => [active_customer, inactive_customer, deleted_customer], "next_cursor" => nil})
      end

      it "skips them" do
        result = customers_service.call

        expect(result.customers.map(&:external_id)).to eq(["58"])
        expect(integration.integration_items.pluck(:external_id)).to eq(["58"])
      end
    end

    context "with existing integration items" do
      let(:other_integration) { create(:quickbooks_integration, organization: create(:organization)) }
      let!(:old_customer) { create(:integration_item, integration:, item_type: :customer, external_id: "1") }
      let!(:standard_item) { create(:integration_item, integration:, item_type: :standard, external_id: "2") }
      let!(:account_item) { create(:integration_item, integration:, item_type: :account, external_id: "3") }
      let!(:other_customer) { create(:integration_item, integration: other_integration, item_type: :customer, external_id: "4") }

      it "replaces only the customer items of the integration" do
        customers_service.call

        expect(IntegrationItem.exists?(old_customer.id)).to be(false)
        expect(integration.integration_items.customer.pluck(:external_id)).to contain_exactly("58", "59")
        expect(integration.integration_items.where.not(item_type: :customer)).to contain_exactly(standard_item, account_item)
        expect(other_customer.reload.external_id).to eq("4")
      end
    end

    context "when the response has a next cursor" do
      let(:second_page) do
        {
          "records" => [aggregator_response["records"].first.merge("id" => "62", "display_name" => "Page Two Ltd")],
          "next_cursor" => nil
        }
      end

      before do
        allow(lago_client).to receive(:get)
          .with(headers:, params:)
          .and_return(aggregator_response.merge("next_cursor" => "cursor-abc"))
        allow(lago_client).to receive(:get)
          .with(headers:, params: params.merge(cursor: "cursor-abc"))
          .and_return(second_page)
      end

      it "fetches the next pages until the cursor is blank" do
        result = customers_service.call

        expect(lago_client).to have_received(:get).twice
        expect(result.customers.map(&:external_id)).to eq(%w[58 59 62])
      end
    end

    context "when every response has a next cursor" do
      before do
        allow(lago_client).to receive(:get)
          .with(headers: anything, params: anything)
          .and_return({"records" => [], "next_cursor" => "c"})
      end

      it "stops after the maximum number of requests" do
        customers_service.call

        expect(lago_client).to have_received(:get).exactly(15).times
      end
    end

    context "when fetching a subsequent page fails" do
      let!(:old_customer) { create(:integration_item, integration:, item_type: :customer, external_id: "1") }

      before do
        allow(lago_client).to receive(:get)
          .with(headers:, params:)
          .and_return(aggregator_response.merge("next_cursor" => "cursor-abc"))
        allow(lago_client).to receive(:get)
          .with(headers:, params: params.merge(cursor: "cursor-abc"))
          .and_raise(StandardError, "aggregator unavailable")
      end

      it "raises and keeps the existing customer items" do
        expect { customers_service.call }.to raise_error(StandardError, "aggregator unavailable")

        expect(integration.integration_items.customer.pluck(:id)).to eq([old_customer.id])
      end
    end
  end

  describe "#fetch_records" do
    subject(:method_call) { customers_service.send(:fetch_records, limit: described_class::LIMIT, cursor: "next_cursor_value") }

    let(:lago_client) { instance_double(LagoHttpClient::Client, get: {}) }

    before { allow(LagoHttpClient::Client).to receive(:new).and_return(lago_client) }

    it "requests the Customer records" do
      method_call

      expect(lago_client).to have_received(:get)
        .with(headers: anything, params: {model: "Customer", limit: described_class::LIMIT, cursor: "next_cursor_value"})
    end
  end
end
