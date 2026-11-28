# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::ConnectionService do
  subject(:result) { described_class.call(integration:) }

  let(:organization) { create(:organization) }
  let(:integration) { build(:quickbooks_integration, organization:, secrets: {connection_id:}.to_json, settings:) }
  let(:connection_id) { "quickbooks-test-connection" }
  let(:sandbox) { false }
  let(:settings) { {realm_id: nil, sandbox:, sync_invoices: false, sync_credit_notes: false, sync_payments: false} }
  let(:provider_config_key) { "quickbooks" }
  let(:encoded_connection_id) { connection_id }
  let(:connection_url) do
    "https://api.nango.dev/connection/#{encoded_connection_id}?provider_config_key=#{provider_config_key}"
  end
  let(:request_headers) do
    {
      "Connection-Id" => connection_id,
      "Authorization" => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      "Provider-Config-Key" => provider_config_key
    }
  end
  let(:response_status) { 200 }
  let(:response_body) do
    {
      "connection_config" => {"realmId" => "1234567890"},
      "credentials" => {"access_token" => "fake-access-token"}
    }.to_json
  end
  let(:log_output) { StringIO.new }

  before do
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log_output))

    stub_request(:get, connection_url)
      .with(headers: request_headers)
      .to_return(status: response_status, body: response_body, headers: {"Content-Type" => "application/json"})
  end

  shared_examples "a generic lookup failure" do
    it "returns a third party failure without the Nango body" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      expect(result.error.third_party).to eq("Nango")
      expect(result.error.error_code).to eq("connection_lookup_failed")
      expect(result.error.message).to eq("Nango: connection_lookup_failed - QuickBooks connection lookup failed")
      expect(result.error.message).not_to include("fake-access-token")
      expect(log_output.string).not_to include("fake-access-token")
    end
  end

  shared_examples "a missing realm id" do
    it "returns a third party failure, since the company id comes from Nango and not from the input" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      expect(result.error.third_party).to eq("Nango")
      expect(result.error.error_code).to eq("realm_id_missing")
      expect(result.error.message).to eq("Nango: realm_id_missing - QuickBooks connection has no company id")
      expect(result.error.message).not_to include("fake-access-token")
      expect(log_output.string).not_to include("fake-access-token")
    end
  end

  context "when Nango returns the connection" do
    it "returns the realm id" do
      expect(result).to be_success
      expect(result.realm_id).to eq("1234567890")
      expect(log_output.string).not_to include("fake-access-token")
      expect(WebMock).to have_requested(:get, connection_url).with(headers: request_headers).once
    end
  end

  context "when the integration is flagged with a realm id mismatch" do
    let(:settings) { {realm_id: "1234567890", realm_id_mismatch: true, sandbox:} }

    it "still asks Nango and returns the realm id" do
      expect(integration.realm_id_mismatch?).to eq(true)
      expect(result).to be_success
      expect(result.realm_id).to eq("1234567890")
      expect(WebMock).to have_requested(:get, connection_url).with(headers: request_headers).once
      expect(log_output.string).not_to include("QuickBooks call blocked")
    end
  end

  context "when the integration is a sandbox" do
    let(:sandbox) { true }
    let(:provider_config_key) { "quickbooks-sandbox" }

    it "asks Nango with the sandbox provider config key" do
      expect(result).to be_success
      expect(result.realm_id).to eq("1234567890")
      expect(WebMock).to have_requested(:get, connection_url).with(headers: request_headers).once
    end
  end

  context "when the realm id is numeric" do
    let(:response_body) { {"connection_config" => {"realmId" => 123}}.to_json }

    it "returns the realm id as a string" do
      expect(result).to be_success
      expect(result.realm_id).to eq("123")
    end
  end

  context "when the connection id contains reserved characters" do
    let(:connection_id) { "quickbooks/test?connection" }
    let(:encoded_connection_id) { "quickbooks%2Ftest%3Fconnection" }

    it "percent-encodes the connection id in the path" do
      expect(result).to be_success
      expect(result.realm_id).to eq("1234567890")
      expect(WebMock).to have_requested(:get, connection_url).once
    end
  end

  context "when Nango returns a 404" do
    let(:response_status) { 404 }
    let(:response_body) { {"error" => "fake-access-token not found"}.to_json }

    it "returns a connection not found failure, the answer for a connection made in the other environment" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      expect(result.error.third_party).to eq("Nango")
      expect(result.error.error_code).to eq("connection_not_found")
      expect(result.error.message).to eq("Nango: connection_not_found - QuickBooks connection not found for this environment")
      expect(result.error.message).not_to include("fake-access-token")
    end

    it "logs the status and the provider config key, never the body or the connection id" do
      result

      expect(log_output.string).to include("QuickBooks connection lookup failed")
      expect(log_output.string).to include('"status":"404"')
      expect(log_output.string).to include('"provider_config_key":"quickbooks"')
      expect(log_output.string).to include(organization.id)
      expect(log_output.string).not_to include("fake-access-token")
      expect(log_output.string).not_to include(connection_id)
    end
  end

  context "when Nango returns a 500" do
    let(:response_status) { 500 }
    let(:response_body) { {"error" => "fake-access-token server error"}.to_json }

    it_behaves_like "a generic lookup failure"

    it "does not retry the request" do
      result

      expect(WebMock).to have_requested(:get, connection_url).once
    end

    it "logs the status without the body" do
      result

      expect(log_output.string).to include('"status":"500"')
      expect(log_output.string).not_to include("fake-access-token")
    end
  end

  context "when Nango returns a body that is not JSON" do
    let(:response_body) { "<html>fake-access-token</html>" }

    it_behaves_like "a generic lookup failure"
  end

  context "when the request times out" do
    before do
      stub_request(:get, connection_url).to_timeout
    end

    it_behaves_like "a generic lookup failure"
  end

  context "when Nango is slow to answer" do
    before do
      stub_request(:get, connection_url).to_raise(Net::ReadTimeout)
    end

    it_behaves_like "a generic lookup failure"

    it "gives up after one request and logs the error class" do
      result

      expect(WebMock).to have_requested(:get, connection_url).once
      expect(log_output.string).to include('"error":"Net::ReadTimeout"')
    end
  end

  [Errno::ENETUNREACH, Errno::EADDRNOTAVAIL].each do |error_class|
    context "when connecting fails with #{error_class}" do
      before do
        stub_request(:get, connection_url).to_raise(error_class)
      end

      it_behaves_like "a generic lookup failure"
    end
  end

  it "builds its HTTP client with short timeouts and no retry, Net::HTTP's own retry included" do
    http_clients = []
    allow(LagoHttpClient::Client).to receive(:new).and_call_original
    allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |http| http_clients << http }
    end

    result

    expect(LagoHttpClient::Client).to have_received(:new)
      .with(a_string_including("connection/"), open_timeout: 5, read_timeout: 10, write_timeout: 10, max_retries: 0)
    expect(http_clients).not_to be_empty
    http_clients.each do |http|
      expect([http.open_timeout, http.read_timeout, http.write_timeout, http.max_retries]).to eq([5, 10, 10, 0])
    end
  end

  context "when the response has no connection_config" do
    let(:response_body) { {"credentials" => {"access_token" => "fake-access-token"}}.to_json }

    it_behaves_like "a missing realm id"
  end

  context "when connection_config is a string" do
    let(:response_body) { {"connection_config" => "realmId=1234567890 fake-access-token"}.to_json }

    it_behaves_like "a missing realm id"
  end

  context "when the realm id is empty" do
    let(:response_body) { {"connection_config" => {"realmId" => ""}}.to_json }

    it_behaves_like "a missing realm id"
  end

  context "when the response body is a JSON array" do
    let(:response_body) { [{"connection_config" => {"realmId" => "1234567890"}}].to_json }

    it_behaves_like "a missing realm id"
  end
end
