# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhooksController, type: :request do
  describe "POST /stripe" do
    let(:organization_id) { Faker::Internet.uuid }
    let(:code) { "stripe_1" }
    let(:signature) { "signature" }
    let(:event_type) { "payment_intent.succeeded" }

    let(:event) do
      path = Rails.root.join("spec/fixtures/stripe/payment_intent_event.json")
      JSON.parse(File.read(path))
    end

    let(:payload) { event.merge(code:) }
    let(:result) { BaseService::Result.new }

    before do
      allow(InboundWebhooks::CreateService)
        .to receive(:call)
        .with(
          organization_id:,
          webhook_source: :stripe,
          code:,
          payload: payload.to_json,
          signature:,
          event_type:
        )
        .and_return(result)
    end

    it "handle stripe webhooks" do
      post(
        "/webhooks/stripe/#{organization_id}",
        params: payload.to_json,
        headers: {
          "HTTP_STRIPE_SIGNATURE" => signature,
          "Content-Type" => "application/json"
        }
      )

      expect(response).to have_http_status(:success)
      expect(InboundWebhooks::CreateService).to have_received(:call)
    end

    context "when InboundWebhooks::CreateService is not successful" do
      before do
        result.record_validation_failure!(record: build(:inbound_webhook))
      end

      it "returns a bad request" do
        post(
          "/webhooks/stripe/#{organization_id}",
          params: payload.to_json,
          headers: {
            "HTTP_STRIPE_SIGNATURE" => signature,
            "Content-Type" => "application/json"
          }
        )

        expect(response).to have_http_status(:bad_request)
        expect(InboundWebhooks::CreateService).to have_received(:call)
      end
    end
  end

  describe "POST /gocardless" do
    let(:organization) { create(:organization) }

    let(:gocardless_provider) do
      create(
        :gocardless_provider,
        organization:,
        webhook_secret: "secrets"
      )
    end

    let(:gocardless_service) { instance_double(PaymentProviders::GocardlessService) }

    let(:events) do
      path = Rails.root.join("spec/fixtures/gocardless/events.json")
      JSON.parse(File.read(path))
    end

    let(:result) do
      result = BaseService::Result.new
      result.events = events["events"].map { |event| GoCardlessPro::Resources::Event.new(event) }
      result
    end

    before do
      allow(PaymentProviders::Gocardless::HandleIncomingWebhookService).to receive(:call)
        .with(
          organization_id: organization.id,
          code: nil,
          body: events.to_json,
          signature: "signature"
        )
        .and_return(result)
    end

    it "handle gocardless webhooks" do
      post(
        "/webhooks/gocardless/#{gocardless_provider.organization_id}",
        params: events.to_json,
        headers: {
          "Webhook-Signature" => "signature",
          "Content-Type" => "application/json"
        }
      )

      expect(response).to have_http_status(:success)

      expect(PaymentProviders::Gocardless::HandleIncomingWebhookService).to have_received(:call)
    end

    context "when failing to handle gocardless event" do
      let(:result) do
        BaseService::Result.new.service_failure!(code: "webhook_error", message: "Invalid payload")
      end

      it "returns a bad request" do
        post(
          "/webhooks/gocardless/#{gocardless_provider.organization_id}",
          params: events.to_json,
          headers: {
            "Webhook-Signature" => "signature",
            "Content-Type" => "application/json"
          }
        )

        expect(response).to have_http_status(:bad_request)

        expect(PaymentProviders::Gocardless::HandleIncomingWebhookService).to have_received(:call)
      end
    end
  end

  describe "POST /adyen" do
    let(:organization) { create(:organization) }

    let(:adyen_provider) do
      create(:adyen_provider, organization:)
    end

    let(:body) do
      path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_response.json")
      JSON.parse(File.read(path))
    end

    let(:result) do
      result = BaseService::Result.new
      result.body = body
      result
    end

    before do
      allow(PaymentProviders::Adyen::HandleIncomingWebhookService).to receive(:call)
        .with(
          organization_id: organization.id,
          code: nil,
          body: body["notificationItems"].first&.dig("NotificationRequestItem")
        )
        .and_return(result)
    end

    it "handle adyen webhooks" do
      post(
        "/webhooks/adyen/#{adyen_provider.organization_id}",
        params: body.to_json,
        headers: {
          "Content-Type" => "application/json"
        }
      )

      expect(response).to have_http_status(:success)
      expect(PaymentProviders::Adyen::HandleIncomingWebhookService).to have_received(:call)
    end

    context "when failing to handle adyen event" do
      let(:result) do
        BaseService::Result.new.service_failure!(code: "webhook_error", message: "Invalid payload")
      end

      it "returns a bad request" do
        post(
          "/webhooks/adyen/#{adyen_provider.organization_id}",
          params: body.to_json,
          headers: {
            "Content-Type" => "application/json"
          }
        )

        expect(response).to have_http_status(:bad_request)
        expect(PaymentProviders::Adyen::HandleIncomingWebhookService).to have_received(:call)
      end
    end
  end

  describe "POST /cashfree" do
    let(:organization) { create(:organization) }

    let(:cashfree_provider) do
      create(:cashfree_provider, organization:)
    end

    let(:cashfree_service) { instance_double(PaymentProviders::CashfreeService) }

    let(:body) do
      path = Rails.root.join("spec/fixtures/cashfree/payment_link_event_payment.json")
      JSON.parse(File.read(path))
    end

    let(:result) do
      result = BaseService::Result.new
      result.body = body
      result
    end

    before do
      allow(PaymentProviders::CashfreeService).to receive(:new)
        .and_return(cashfree_service)
      allow(cashfree_service).to receive(:handle_incoming_webhook)
        .with(
          organization_id: organization.id,
          code: nil,
          body: body.to_json,
          timestamp: "1629271506",
          signature: "MFB3Rkubs4jB97ROS/I4iu9llAAP5ykJ3GZYp95o/Mw="
        )
        .and_return(result)
    end

    it "handle cashfree webhooks" do
      post(
        "/webhooks/cashfree/#{cashfree_provider.organization_id}",
        params: body.to_json,
        headers: {
          "Content-Type" => "application/json",
          "X-Cashfree-Timestamp" => "1629271506",
          "X-Cashfree-Signature" => "MFB3Rkubs4jB97ROS/I4iu9llAAP5ykJ3GZYp95o/Mw="
        }
      )

      expect(response).to have_http_status(:success)

      expect(PaymentProviders::CashfreeService).to have_received(:new)
      expect(cashfree_service).to have_received(:handle_incoming_webhook)
    end

    context "when failing to handle cashfree event" do
      let(:result) do
        BaseService::Result.new.service_failure!(code: "webhook_error", message: "Invalid payload")
      end

      it "returns a bad request" do
        post(
          "/webhooks/cashfree/#{cashfree_provider.organization_id}",
          params: body.to_json,
          headers: {
            "Content-Type" => "application/json",
            "X-Cashfree-Timestamp" => "1629271506",
            "X-Cashfree-Signature" => "MFB3Rkubs4jB97ROS/I4iu9llAAP5ykJ3GZYp95o/Mw="
          }
        )

        expect(response).to have_http_status(:bad_request)

        expect(PaymentProviders::CashfreeService).to have_received(:new)
        expect(cashfree_service).to have_received(:handle_incoming_webhook)
      end
    end
  end
end
