# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::AdyenService do
  let(:adyen_service) { described_class.new(adyen_customer) }
  let(:customer) { create(:customer, organization:) }
  let(:adyen_provider) { create(:adyen_provider) }
  let(:organization) { adyen_provider.organization }
  let(:adyen_client) { instance_double(Adyen::Client) }
  let(:payment_links_api) { Adyen::PaymentLinksApi.new(adyen_client, 70) }
  let(:checkout) { Adyen::Checkout.new(adyen_client, 70) }
  let(:payment_links_response) { generate(:adyen_payment_links_response) }

  let(:adyen_customer) do
    create(:adyen_customer, customer:, provider_customer_id: nil)
  end

  before do
    allow(Adyen::Client).to receive(:new).and_return(adyen_client)
    allow(adyen_client).to receive(:checkout).and_return(checkout)
    allow(checkout).to receive(:payment_links_api).and_return(payment_links_api)
    allow(payment_links_api).to receive(:payment_links).and_return(payment_links_response)
  end

  describe "#create" do
    subject(:adyen_service_create) { adyen_service.create }

    context "when customer does not have an adyen customer id yet" do
      it "calls adyen api client payment links" do
        adyen_service_create
        expect(payment_links_api).to have_received(:payment_links)
      end

      it "creates a payment link" do
        expect(adyen_service_create.checkout_url).to eq("https://test.adyen.link/test")
      end

      it "delivers a success webhook" do
        expect { adyen_service_create }.to enqueue_job(SendWebhookJob)
          .with(
            "customer.checkout_url_generated",
            customer,
            checkout_url: "https://test.adyen.link/test"
          )
          .on_queue(webhook_queue)
      end
    end

    context "when customer already has an adyen customer id" do
      let(:adyen_customer) do
        create(:adyen_customer, customer:, provider_customer_id: "cus_123456")
      end

      it "does not call adyen API" do
        expect(payment_links_api).not_to have_received(:payment_links)
      end
    end

    context "when failing to generate the checkout link due to an error response" do
      let(:payment_links_error_response) { generate(:adyen_payment_links_error_response) }

      before do
        allow(payment_links_api).to receive(:payment_links).and_return(payment_links_error_response)
      end

      it "delivers an error webhook" do
        expect { adyen_service_create }.to enqueue_job(SendWebhookJob)
          .with(
            "customer.payment_provider_error",
            customer,
            provider_error: {
              message: "There are no payment methods available for the given parameters.",
              error_code: "validation"
            }
          ).on_queue(webhook_queue)
      end
    end

    context "when failing to generate the checkout link" do
      before do
        allow(payment_links_api)
          .to receive(:payment_links).and_raise(Adyen::AdyenError.new(nil, nil, "error"))
      end

      it "delivers an error webhook" do
        expect { adyen_service.create }
          .to raise_error(Adyen::AdyenError)

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "customer.payment_provider_error",
            customer,
            provider_error: {
              message: "error",
              error_code: nil
            }
          )
      end
    end

    context "with authentication error" do
      before do
        allow(payment_links_api)
          .to receive(:payment_links).and_raise(Adyen::AuthenticationError.new("error", nil))
      end

      it "delivers an error webhook" do
        expect(adyen_service.create).to be_success

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "customer.payment_provider_error",
            customer,
            provider_error: {
              message: "error",
              error_code: 401
            }
          )
      end
    end
  end

  describe "#update" do
    it "returns result" do
      expect(adyen_service.update).to be_a(BaseService::Result)
    end
  end

  describe "#success_redirect_url" do
    subject(:success_redirect_url) { adyen_service.__send__(:success_redirect_url) }

    context "when payment provider has success redirect url" do
      it "returns payment provider's success redirect url" do
        expect(success_redirect_url).to eq(adyen_provider.success_redirect_url)
      end
    end

    context "when payment provider has no success redirect url" do
      let(:adyen_provider) { create(:adyen_provider, success_redirect_url: nil) }

      it "returns the default success redirect url" do
        expect(success_redirect_url).to eq(PaymentProviders::AdyenProvider::SUCCESS_REDIRECT_URL)
      end
    end
  end

  describe "#generate_checkout_url" do
    context "when adyen payment provider is nil" do
      before { adyen_provider.destroy! }

      it "returns a not found error" do
        result = adyen_service.generate_checkout_url

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("adyen_payment_provider_not_found")
        end
      end
    end

    context "when adyen payment provider is present" do
      subject(:generate_checkout_url) { adyen_service.generate_checkout_url }

      it "generates a checkout url" do
        expect(generate_checkout_url).to be_success
      end

      it "delivers a success webhook" do
        expect { generate_checkout_url }.to enqueue_job(SendWebhookJob)
          .with(
            "customer.checkout_url_generated",
            customer,
            checkout_url: "https://test.adyen.link/test"
          )
          .on_queue(webhook_queue)
      end
    end
  end
end
