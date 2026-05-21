# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::MoneyhashService do
  subject(:moneyhash_service) { described_class.new(invoice) }

  let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :subscription, payment_status: :pending) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:moneyhash_provider) { create(:moneyhash_provider, organization:) }
  let(:moneyhash_customer) { create(:moneyhash_customer, customer:, payment_provider: moneyhash_provider) }

  let(:intent_processed_json) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/intent.processed.json"))) }
  let(:provider_payment_id) { intent_processed_json.dig("data", "id") }

  let(:mh_provider_service) { PaymentProviders::MoneyhashService.new }

  let(:payment_url_response) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/checkout_url_response.json"))) }

  describe "#update_payment_status" do
    before do
      intent_processed_json["data"]["intent"]["custom_fields"]["lago_payable_id"] = invoice.id

      moneyhash_provider
      moneyhash_customer
    end

    it "creates a payment and updates the invoice payment status" do
      result = moneyhash_service.update_payment_status(
        organization_id: organization.id,
        provider_payment_id: intent_processed_json.dig("data", "intent_id"),
        status: "SUCCESSFUL",
        metadata: intent_processed_json.dig("data", "intent", "custom_fields")
      ).raise_if_error!

      expect(result).to be_success
      expect(result.payment.status).to eq("succeeded")
      expect(result.payment.provider_payment_id).to eq(intent_processed_json.dig("data", "intent_id"))
      expect(result.payment.payable_payment_status).to eq("succeeded")
      expect(result.invoice.payment_status).to eq("succeeded")
      expect(result.invoice.payment_attempts).to eq(1)
    end

    it "enqueues a SendWebhookJob for payment.succeeded" do
      expect do
        moneyhash_service.update_payment_status(
          organization_id: organization.id,
          provider_payment_id: intent_processed_json.dig("data", "intent_id"),
          status: "SUCCESSFUL",
          metadata: intent_processed_json.dig("data", "intent", "custom_fields")
        )
      end.to have_enqueued_job(SendWebhookJob).with("payment.succeeded", Payment)
    end
  end

  describe "#generate_payment_url" do
    let(:response) { instance_double(Net::HTTPOK) }
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:endpoint) { "#{PaymentProviders::MoneyhashProvider.api_base_url}/api/v1.1/payments/intent/" }
    let(:payment_intent) { create(:payment_intent) }

    before do
      allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
      allow(lago_client).to receive(:post_with_response).and_return(response)
      allow(response).to receive(:body).and_return(payment_url_response.to_json)

      moneyhash_provider
      moneyhash_customer
    end

    it "generates the payment url" do
      result = moneyhash_service.generate_payment_url(payment_intent)
      expect(result).to be_success
      expect(result.payment_url).to eq("#{payment_url_response.dig("data", "embed_url")}?lago_request=generate_payment_url")
    end

    it "exposes the provider session id" do
      result = moneyhash_service.generate_payment_url(payment_intent)
      expect(result.provider_session_id).to eq(payment_url_response.dig("data", "id"))
    end
  end

  describe "#checkout_session_already_completed?" do
    let(:payment_intent) { create(:payment_intent, invoice:, provider_session_id: "MH123") }
    let(:base) { ::PaymentProviders::MoneyhashProvider.api_base_url }
    let(:intent_endpoint) { "#{base}/api/v1.1/payments/intent/MH123/" }
    let(:intent_client) { instance_double(LagoHttpClient::Client) }
    let(:status) { "INITIATED" }
    let(:get_response) { instance_double(Net::HTTPOK, body: {data: {status:}}.to_json) }

    before do
      moneyhash_provider
      moneyhash_customer

      allow(LagoHttpClient::Client).to receive(:new).with(intent_endpoint).and_return(intent_client)
      allow(intent_client).to receive(:get).and_return(get_response)
    end

    it "returns false for non-paid intents" do
      expect(moneyhash_service.checkout_session_already_completed?(payment_intent)).to be false
    end

    %w[PROCESSED SUCCESSFUL].each do |s|
      context "when status is #{s}" do
        let(:status) { s }

        it "returns true" do
          expect(moneyhash_service.checkout_session_already_completed?(payment_intent)).to be true
        end
      end
    end

    it "returns false when provider_session_id is missing" do
      payment_intent.update!(provider_session_id: nil)
      expect(moneyhash_service.checkout_session_already_completed?(payment_intent)).to be false
    end

    it "swallows HTTP errors and returns false" do
      allow(intent_client).to receive(:get).and_raise(LagoHttpClient::HttpError.new(500, "boom", nil))
      expect(moneyhash_service.checkout_session_already_completed?(payment_intent)).to be false
    end

    it "swallows network timeouts so auto-charge isn't blocked" do
      allow(intent_client).to receive(:get).and_raise(Net::ReadTimeout)
      expect(moneyhash_service.checkout_session_already_completed?(payment_intent)).to be false
    end
  end

  describe "#expire_checkout_session" do
    let(:payment_intent) { create(:payment_intent, invoice:, provider_session_id: "MH123") }
    let(:base) { ::PaymentProviders::MoneyhashProvider.api_base_url }
    let(:close_endpoint) { "#{base}/api/v1.1/payments/intent/MH123/close/" }
    let(:close_client) { instance_double(LagoHttpClient::Client) }

    before do
      moneyhash_provider
      moneyhash_customer

      allow(LagoHttpClient::Client).to receive(:new).with(close_endpoint).and_return(close_client)
      allow(close_client).to receive(:post_with_response).and_return(instance_double(Net::HTTPOK))
    end

    it "POSTs to the close endpoint" do
      moneyhash_service.expire_checkout_session(payment_intent)
      expect(close_client).to have_received(:post_with_response)
    end

    it "does nothing when provider_session_id is missing" do
      payment_intent.update!(provider_session_id: nil)
      allow(LagoHttpClient::Client).to receive(:new).and_return(close_client)

      moneyhash_service.expire_checkout_session(payment_intent)

      expect(close_client).not_to have_received(:post_with_response)
    end

    it "swallows 4xx HTTP errors (terminal: intent processed / not found)" do
      allow(close_client).to receive(:post_with_response)
        .and_raise(LagoHttpClient::HttpError.new(400, "already processed", nil))
      expect { moneyhash_service.expire_checkout_session(payment_intent) }.not_to raise_error
    end

    it "wraps 5xx HTTP errors as Invoices::Payments::ConnectionError" do
      allow(close_client).to receive(:post_with_response)
        .and_raise(LagoHttpClient::HttpError.new(503, "service unavailable", nil))
      expect { moneyhash_service.expire_checkout_session(payment_intent) }
        .to raise_error(Invoices::Payments::ConnectionError)
    end

    it "wraps 429 HTTP errors as Invoices::Payments::RateLimitError" do
      allow(close_client).to receive(:post_with_response)
        .and_raise(LagoHttpClient::HttpError.new(429, "slow down", nil))
      expect { moneyhash_service.expire_checkout_session(payment_intent) }
        .to raise_error(Invoices::Payments::RateLimitError)
    end
  end
end
