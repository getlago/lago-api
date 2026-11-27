# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::Contacts::FindQuickbooksCustomerService do
  subject(:result) { described_class.call(integration:, display_name:, notes_marker:) }

  let(:organization) { create(:organization) }
  let(:integration) { create(:quickbooks_integration, organization:, settings:) }
  let(:realm_id) { "1234567890" }
  let(:settings) { {realm_id:, sandbox: false, sync_invoices: false, sync_credit_notes: false, sync_payments: false} }
  let(:display_name) { "Example Co" }
  let(:notes_marker) { "Lago customer: 1a2b3c" }
  let(:connection_id) { "quickbooks-test-connection" }
  let(:search_url) { "https://api.nango.dev/proxy/v3/company/1234567890/query" }
  let(:query) { "select Id, Notes from Customer where DisplayName = 'Example Co'" }
  let(:request_headers) { {"Connection-Id" => connection_id, "Provider-Config-Key" => "quickbooks"} }
  let(:response_status) { 200 }
  let(:customers) { [{Id: "77", Notes: "Lago customer: 1a2b3c (cust-ext-1)"}] }
  let(:response_body) { {QueryResponse: {Customer: customers}}.to_json }
  let(:log_output) { StringIO.new }

  before do
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log_output))

    stub_request(:get, search_url)
      .with(query: hash_including({}))
      .to_return(status: response_status, body: response_body, headers: {"Content-Type" => "application/json"})
  end

  shared_examples "a customer search failure" do
    it "fails with customer_lookup_failed without the realm id or the Nango body" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("customer_lookup_failed")
      expect(result.error.error_message).to eq("QuickBooks customer lookup failed")
      expect(result.error.message).not_to include(realm_id)
      expect(result.error.message).not_to include("fake-intuit-detail")
    end

    it "logs neither the realm id, the connection id nor the body" do
      result

      expect(log_output.string).to include("QuickBooks customer search failed")
      expect(log_output.string).not_to include(realm_id)
      expect(log_output.string).not_to include(connection_id)
      expect(log_output.string).not_to include("fake-intuit-detail")
    end
  end

  context "when the customer holding the name has the marker in its Notes" do
    it "returns its id" do
      expect(result).to be_success
      expect(result.contact_id).to eq("77")
      expect(WebMock).to have_requested(:get, search_url).with(query: {"query" => query}, headers: request_headers).once
    end
  end

  context "when the customer holding the name has other Notes" do
    let(:customers) { [{Id: "12", Notes: "Imported from the old ERP"}] }

    it "returns no id" do
      expect(result).to be_success
      expect(result.contact_id).to be_nil
    end
  end

  context "when no customer holds the name" do
    let(:response_body) { {QueryResponse: {}}.to_json }

    it "returns no id" do
      expect(result).to be_success
      expect(result.contact_id).to be_nil
    end
  end

  context "when the name contains a single quote and a backslash" do
    let(:display_name) { "O'Brien \\ Co" }

    it "escapes both in the query" do
      result

      expect(WebMock).to have_requested(:get, search_url)
        .with(query: {"query" => "select Id, Notes from Customer where DisplayName = 'O\\'Brien \\\\ Co'"}).once
    end
  end

  context "when the realm id is blank" do
    let(:realm_id) { nil }

    it "fails with realm_id_missing without calling Nango" do
      expect(result.error.code).to eq("realm_id_missing")
      expect(WebMock).not_to have_requested(:any, /nango/)
    end
  end

  context "when Nango returns a 500" do
    let(:response_status) { 500 }
    let(:response_body) { {error: "fake-intuit-detail"}.to_json }

    it_behaves_like "a customer search failure"
  end

  context "when Nango returns a body that is not JSON" do
    let(:response_body) { "<html>fake-intuit-detail</html>" }

    it_behaves_like "a customer search failure"
  end

  context "when Nango returns a 429" do
    let(:response_status) { 429 }
    let(:response_body) { {Fault: {Error: [{code: "3001"}], type: "ThrottlingFault"}}.to_json }

    it "raises NextWindowThrottlingError" do
      expect { result }.to raise_error(BaseService::NextWindowThrottlingError)
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
end
