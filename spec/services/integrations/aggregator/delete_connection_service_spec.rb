# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::DeleteConnectionService do
  subject(:result) { described_class.call(integration:) }

  let(:organization) { create(:organization) }
  let(:integration) { create(:quickbooks_integration, organization:, secrets: {connection_id:}.to_json, settings:) }
  let(:connection_id) { "quickbooks-delete-connection" }
  let(:sandbox) { false }
  let(:settings) { {realm_id: "1234567890", sandbox:, sync_invoices: false, sync_credit_notes: false, sync_payments: false} }
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
  let(:response_status) { 204 }
  let(:response_body) { "" }
  let(:log_output) { StringIO.new }
  let(:other_settings) { settings.merge(realm_id: "9876543210") }

  before do
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log_output))

    stub_request(:delete, connection_url)
      .with(headers: request_headers)
      .to_return(status: response_status, body: response_body)
  end

  shared_examples "a silent skip" do
    it "sends no request to Nango and logs nothing" do
      expect(result).to be_success
      expect(a_request(:delete, /api\.nango\.dev/)).not_to have_been_made
      expect(log_output.string).to be_empty
    end
  end

  shared_examples "a logged failure" do |error_class, status|
    it "succeeds after one request and logs one safe line" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:delete, connection_url).once

      lines = log_output.string.lines
      expect(lines.size).to eq(1)
      expect(lines.first).to include("QuickBooks connection deletion failed")
      expect(lines.first).to include(organization.id)
      expect(lines.first).to include('"provider_config_key":"quickbooks"')
      expect(lines.first).to include(%("error":"#{error_class}"))
      if status
        expect(lines.first).to include(%("status":"#{status}"))
      else
        expect(lines.first).not_to include('"status"')
      end
      expect(lines.first).not_to include(connection_id)
      expect(lines.first).not_to include("fake-access-token")
    end
  end

  context "when Nango deletes the connection" do
    it "sends one DELETE with the Nango bearer token and logs nothing" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:delete, connection_url).with(headers: request_headers).once
      expect(log_output.string).to be_empty
    end
  end

  context "when the integration is flagged as pointing at another company" do
    let(:settings) { {realm_id: "1234567890", sandbox:, realm_id_mismatch: true} }

    it "still sends the DELETE, as the connection holds tokens for that company" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:delete, connection_url).with(headers: request_headers).once
      expect(log_output.string).not_to include("realm id changed")
    end
  end

  context "when the integration is a sandbox" do
    let(:sandbox) { true }
    let(:provider_config_key) { "quickbooks-sandbox" }

    it "deletes it with the sandbox provider config key" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:delete, connection_url).with(headers: request_headers).once
    end
  end

  context "when the connection id contains reserved characters" do
    let(:connection_id) { "a/b?c d" }
    let(:encoded_connection_id) { "a%2Fb%3Fc%20d" }

    it "percent-encodes the connection id in the path" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:delete, connection_url).once
    end
  end

  context "when the connection id is blank" do
    let(:integration) { build(:quickbooks_integration, organization:, secrets: {connection_id: ""}.to_json) }

    it_behaves_like "a silent skip"
  end

  context "when another QuickBooks integration of the same organization uses the connection" do
    before do
      create(:quickbooks_integration, organization:, code: "other", secrets: {connection_id:}.to_json, settings: other_settings)
    end

    it_behaves_like "a silent skip"
  end

  context "when a QuickBooks integration of another organization uses the connection" do
    before { create(:quickbooks_integration, secrets: {connection_id:}.to_json, settings: other_settings) }

    it_behaves_like "a silent skip"
  end

  context "when a QuickBooks integration with the other sandbox value uses the connection" do
    before do
      create(
        :quickbooks_integration,
        organization:,
        code: "other",
        secrets: {connection_id:}.to_json,
        settings: other_settings.merge(sandbox: !sandbox)
      )
    end

    it_behaves_like "a silent skip"
  end

  context "when another QuickBooks integration uses a different connection" do
    before do
      create(
        :quickbooks_integration,
        organization:,
        code: "other",
        secrets: {connection_id: "other-connection"}.to_json,
        settings: other_settings
      )
    end

    it "deletes the connection" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:delete, connection_url).once
    end
  end

  context "when a NetSuite integration uses the same connection id" do
    before { create(:netsuite_integration, organization:, secrets: {connection_id:, client_secret: "secret"}.to_json) }

    it "deletes the connection" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:delete, connection_url).once
    end
  end

  context "when Nango returns a 404" do
    let(:response_status) { 404 }
    let(:response_body) { {"error" => "fake-access-token not found"}.to_json }

    it "treats the connection as already deleted and logs nothing" do
      expect(result).to be_success
      expect(WebMock).to have_requested(:delete, connection_url).once
      expect(log_output.string).to be_empty
    end
  end

  context "when Nango returns a 500" do
    let(:response_status) { 500 }
    let(:response_body) { {"error" => "fake-access-token server error"}.to_json }

    it_behaves_like "a logged failure", "LagoHttpClient::HttpError", "500"
  end

  context "when the request times out" do
    before { stub_request(:delete, connection_url).to_timeout }

    it_behaves_like "a logged failure", "Net::OpenTimeout", nil
  end

  context "when Nango is slow to answer" do
    before { stub_request(:delete, connection_url).to_raise(Net::ReadTimeout) }

    it_behaves_like "a logged failure", "Net::ReadTimeout", nil
  end

  context "when the connection is refused" do
    before { stub_request(:delete, connection_url).to_raise(Errno::ECONNREFUSED) }

    it_behaves_like "a logged failure", "Errno::ECONNREFUSED", nil
  end

  context "when an unexpected error is raised" do
    before do
      integration
      allow(Integrations::QuickbooksIntegration).to receive(:where).and_raise(ActiveRecord::Encryption::Errors::Decryption)
    end

    it "succeeds without a request and logs one safe line" do
      expect(result).to be_success
      expect(a_request(:delete, /api\.nango\.dev/)).not_to have_been_made

      lines = log_output.string.lines
      expect(lines.size).to eq(1)
      expect(lines.first).to include('"error":"ActiveRecord::Encryption::Errors::Decryption"')
      expect(lines.first).not_to include(connection_id)
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
end
