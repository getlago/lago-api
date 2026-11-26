# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Contacts::FetchQuickbooksSyncTokenService do
  subject(:result) { described_class.call(integration:, integration_customer:) }

  let(:organization) { create(:organization) }
  let(:integration) { create(:quickbooks_integration, organization:, settings:) }
  let(:sandbox) { false }
  let(:realm_id) { "1234567890" }
  let(:settings) { {realm_id:, sandbox:, sync_invoices: false, sync_credit_notes: false, sync_payments: false} }
  let(:customer) { create(:customer, organization:) }
  let(:integration_customer) { create(:quickbooks_customer, integration:, customer:, external_customer_id: "58") }
  let(:connection_id) { "quickbooks-test-connection" }
  let(:provider_config_key) { "quickbooks" }
  let(:proxy_url) { "https://api.nango.dev/proxy/v3/company/1234567890/customer/58" }
  let(:request_headers) do
    {
      "Connection-Id" => connection_id,
      "Authorization" => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      "Provider-Config-Key" => provider_config_key
    }
  end
  let(:response_status) { 200 }
  let(:response_body) do
    File.read(Rails.root.join("spec/fixtures/integration_aggregator/contacts/quickbooks_customer_proxy_response.json"))
  end
  let(:log_output) { StringIO.new }

  before do
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log_output))

    stub_request(:get, proxy_url)
      .with(headers: request_headers)
      .to_return(status: response_status, body: response_body, headers: {"Content-Type" => "application/json"})
  end

  shared_examples "a customer lookup failure" do
    it "returns a service failure without the realm id or the Nango body" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("customer_lookup_failed")
      expect(result.error.error_message).to eq("QuickBooks customer lookup failed")
      expect(result.error.message).not_to include(realm_id)
      expect(result.error.message).not_to include("fake-intuit-detail")
    end

    it "logs the organization and the provider config key, never the realm id, the connection id or the body" do
      result

      expect(log_output.string).to include("QuickBooks customer lookup failed")
      expect(log_output.string).to include(organization.id)
      expect(log_output.string).to include('"provider_config_key":"quickbooks"')
      expect(log_output.string).not_to include(realm_id)
      expect(log_output.string).not_to include(connection_id)
      expect(log_output.string).not_to include("fake-intuit-detail")
    end
  end

  context "when QuickBooks returns the customer" do
    it "returns its SyncToken and DisplayName" do
      expect(result).to be_success
      expect(result.sync_token).to eq("3")
      expect(result.display_name).to eq("Example Co")
      expect(WebMock).to have_requested(:get, proxy_url).with(headers: request_headers).once
    end
  end

  context "when the SyncToken is numeric" do
    let(:response_body) { {"Customer" => {"Id" => "58", "SyncToken" => 7}}.to_json }

    it "returns it as a string" do
      expect(result).to be_success
      expect(result.sync_token).to eq("7")
    end
  end

  context "when the integration is a sandbox" do
    let(:sandbox) { true }
    let(:provider_config_key) { "quickbooks-sandbox" }

    it "reads the customer with the sandbox provider config key" do
      expect(result).to be_success
      expect(result.sync_token).to eq("3")
      expect(WebMock).to have_requested(:get, proxy_url).with(headers: request_headers).once
    end
  end

  context "when the ids contain reserved characters" do
    let(:realm_id) { "12/34?5" }
    let(:integration_customer) { create(:quickbooks_customer, integration:, customer:, external_customer_id: "5/8") }
    let(:proxy_url) { "https://api.nango.dev/proxy/v3/company/12%2F34%3F5/customer/5%2F8" }

    it "percent-encodes them in the path" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:get, proxy_url).once
    end
  end

  context "when the realm id is blank" do
    let(:realm_id) { nil }

    before { allow(Throttling).to receive(:for).and_call_original }

    it "fails with realm_id_missing without calling Nango or the throttle" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("realm_id_missing")
      expect(result.error.error_message).to eq("QuickBooks connection has no company id")
      expect(WebMock).not_to have_requested(:any, /nango/)
      expect(Throttling).not_to have_received(:for)
    end
  end

  context "when Nango returns a 404" do
    let(:response_status) { 404 }
    let(:response_body) { {"Fault" => {"Error" => [{"Detail" => "fake-intuit-detail"}]}}.to_json }

    it "fails with customer_not_found without the realm id or the Nango body" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("customer_not_found")
      expect(result.error.error_message).to eq("QuickBooks customer not found")
      expect(result.error.message).not_to include(realm_id)
      expect(result.error.message).not_to include("fake-intuit-detail")
    end

    it "logs the HTTP status" do
      result

      expect(log_output.string).to include('"status":"404"')
    end
  end

  context "when Nango returns a 429" do
    let(:response_status) { 429 }
    let(:response_body) { {"Fault" => {"Error" => [{"code" => "3001"}], "type" => "ThrottlingFault"}}.to_json }

    it "raises NextWindowThrottlingError" do
      expect { result }.to raise_error(BaseService::NextWindowThrottlingError)
    end
  end

  context "when Nango returns a 500" do
    let(:response_status) { 500 }
    let(:response_body) { {"error" => "fake-intuit-detail"}.to_json }

    it_behaves_like "a customer lookup failure"

    it "logs the HTTP status" do
      result

      expect(log_output.string).to include('"status":"500"')
    end
  end

  context "when Nango returns a body that is not JSON" do
    let(:response_body) { "<html>fake-intuit-detail</html>" }

    it_behaves_like "a customer lookup failure"

    it "logs the parser error class without a status" do
      result

      expect(log_output.string).to include('"error":"JSON::ParserError"')
      expect(log_output.string).not_to include('"status"')
    end
  end

  context "when the response has no SyncToken" do
    let(:response_body) { {"Customer" => {"Id" => "58", "DisplayName" => "Example Co"}}.to_json }

    it "fails with sync_token_missing" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("sync_token_missing")
      expect(result.error.error_message).to eq("QuickBooks customer has no SyncToken")
    end
  end

  context "when the response is a JSON array" do
    let(:response_body) { [{"Customer" => {"SyncToken" => "3"}}].to_json }

    it "fails with sync_token_missing" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("sync_token_missing")
    end
  end

  context "when the QuickBooks throttle window is full" do
    let(:throttle) { instance_double(Throttling::Base, check: false) }

    before { allow(Throttling).to receive(:for).with(:quickbooks).and_return(throttle) }

    it "raises NextWindowThrottlingError before any request" do
      expect { result }.to raise_error(BaseService::NextWindowThrottlingError)
      expect(WebMock).not_to have_requested(:any, /nango/)
    end
  end

  context "when the QuickBooks throttle window has room" do
    let(:throttle) { instance_double(Throttling::Base, check: true) }

    before { allow(Throttling).to receive(:for).with(:quickbooks).and_return(throttle) }

    it "checks the throttle once before the request" do
      expect(result).to be_success
      expect(throttle).to have_received(:check).with(:client, anything).once
    end
  end
end
