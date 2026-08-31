# frozen_string_literal: true

require "rails_helper"

describe Integrations::Aggregator::Invoices::VoidService do
  subject(:service_call) { described_class.call(invoice:) }

  let(:service) { described_class.new(invoice:) }
  let(:integration) { create(:netsuite_integration, organization:, sync_invoices: true) }
  let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { "https://api.nango.dev/v1/netsuite/invoices/void" }
  let(:invoice) { create(:invoice, customer:, organization:, status: :voided) }

  let(:headers) do
    {
      "Connection-Id" => integration.connection_id,
      "Authorization" => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      "Provider-Config-Key" => "netsuite-tba"
    }
  end

  let(:params) do
    {
      "type" => "void-invoice",
      "payload" => anything
    }
  end

  before do
    allow(LagoHttpClient::Client).to receive(:new)
      .with(endpoint, retries_on: [OpenSSL::SSL::SSLError])
      .and_return(lago_client)

    integration_customer
  end

  describe "#call" do
    context "when integration invoice exists" do
      let(:response) { instance_double(Net::HTTPOK) }

      before do
        create(:integration_resource, integration:, syncable: invoice, resource_type: :invoice)
        allow(lago_client).to receive(:put_with_response).with(params, headers).and_return(response)
      end

      it "voids the invoice on the provider" do
        result = service_call

        expect(result).to be_success
        expect(result.invoice_id).to eq(invoice.id)
        expect(lago_client).to have_received(:put_with_response).with(params, headers)
      end

      it_behaves_like "throttles!", :netsuite
    end

    context "when integration invoice does not exist" do
      it "raises an invoice missing failure" do
        expect { service_call }.to raise_error(Integrations::Aggregator::BasePayload::Failure) do |error|
          expect(error.code).to eq("invoice_missing")
        end
      end
    end

    context "when there is no integration customer" do
      let(:integration_customer) { nil }

      it "returns result without making an API call" do
        result = service_call

        expect(result).to be_success
        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end

    context "when sync invoices is disabled" do
      let(:integration) { create(:netsuite_integration, organization:, sync_invoices: false) }

      it "returns result without making an API call" do
        result = service_call

        expect(result).to be_success
        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end

    context "when the provider is not netsuite" do
      let(:integration) { create(:xero_integration, organization:, sync_invoices: true) }
      let(:integration_customer) { create(:xero_customer, integration:, customer:) }

      it "returns result without making an API call" do
        result = service_call

        expect(result).to be_success
        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end

    context "when the invoice is not voided" do
      let(:invoice) { create(:invoice, customer:, organization:, status: :finalized) }

      it "returns result without making an API call" do
        result = service_call

        expect(result).to be_success
        expect(LagoHttpClient::Client).not_to have_received(:new)
      end
    end

    context "when the http call fails" do
      let(:body) do
        path = Rails.root.join("spec/fixtures/integration_aggregator/error_response.json")
        File.read(path)
      end

      let(:http_error) { LagoHttpClient::HttpError.new(error_code, body, nil) }

      before do
        create(:integration_resource, integration:, syncable: invoice, resource_type: :invoice)
        allow(lago_client).to receive(:put_with_response).with(params, headers).and_raise(http_error)
      end

      context "when it is a server error" do
        let(:error_code) { 500 }

        it "returns an error" do
          expect do
            service_call
          end.to raise_error(http_error)
        end

        it "enqueues a SendWebhookJob" do
          expect { service_call }.to have_enqueued_job(SendWebhookJob).and raise_error(http_error)
        end
      end

      context "when it is a client error" do
        let(:error_code) { 400 }

        it "does not raise an error" do
          expect { service_call }.not_to raise_error
        end

        it "returns a failure result" do
          result = service_call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NonRetryableFailure)
        end

        it "enqueues a SendWebhookJob" do
          expect { service_call }.to have_enqueued_job(SendWebhookJob)
        end
      end
    end
  end
end
