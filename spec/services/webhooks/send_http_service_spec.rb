# frozen_string_literal: true

require "rails_helper"
require "aws-sdk-s3"

RSpec.describe Webhooks::SendHttpService do
  subject(:service) { described_class.new(webhook:) }

  before_all do
    create_default(:organization)
    create_default(:customer)
  end

  let(:webhook_endpoint) { create(:webhook_endpoint, webhook_url: "https://wh.test.com") }
  let(:webhook) { create(:webhook, webhook_endpoint:) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }

  around do |example|
    original_value = ENV["LAGO_WEBHOOK_ATTEMPTS"]
    ENV["LAGO_WEBHOOK_ATTEMPTS"] = "3"
    example.run
  ensure
    ENV["LAGO_WEBHOOK_ATTEMPTS"] = original_value
  end

  context "when client returns a success" do
    before do
      WebMock.stub_request(:post, "https://wh.test.com").to_return(status: 200, body: "ok")
    end

    it "marks the webhook as succeeded" do
      service.call

      expect(WebMock).to have_requested(:post, "https://wh.test.com").with(
        body: webhook.payload.to_json,
        headers: {"Content-Type" => "application/json"}
      )
      expect(webhook.status).to eq "succeeded"
      expect(webhook.http_status).to eq 200
      expect(webhook.response).to eq "ok"
      expect(webhook.response_key).to match(%r{/response\.json\.gz\z})
      expect(webhook.read_attribute(:response)).to be_nil
    end
  end

  context "with a standard_webhooks endpoint" do
    let(:webhook_endpoint) { create(:webhook_endpoint, webhook_url: "https://wh.test.com", signature_algo: :standard_webhooks) }
    let(:webhook) do
      create(
        :webhook,
        webhook_endpoint:,
        id: "8b2f6a1e-3c4d-4e5f-9a6b-7c8d9e0f1a2b",
        payload: {"webhook_type" => "invoice.created", "amount_cents" => 100}
      )
    end

    around { |example| travel_to(Time.zone.at(1_762_300_800)) { example.run } }

    context "when the endpoint has a signing key" do
      before do
        # Secret: whsec_ + base64 of the 32 bytes 0x00..0x1f.
        create(:webhook_endpoint_signing_key, webhook_endpoint:, secret: "whsec_AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=")
        WebMock.stub_request(:post, "https://wh.test.com").to_return(status: 200, body: "ok")
      end

      it "sends the body with the Standard Webhooks headers only" do
        service.call

        # printf '%s' '8b2f6a1e-3c4d-4e5f-9a6b-7c8d9e0f1a2b.1762300800.{"webhook_type":"invoice.created","amount_cents":100}' \
        #   | openssl dgst -sha256 -mac HMAC -macopt hexkey:000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f -binary | base64
        expect(WebMock).to have_requested(:post, "https://wh.test.com").with { |request|
          request.body == '{"webhook_type":"invoice.created","amount_cents":100}' &&
            request.headers["Webhook-Id"] == "8b2f6a1e-3c4d-4e5f-9a6b-7c8d9e0f1a2b" &&
            request.headers["Webhook-Timestamp"] == "1762300800" &&
            request.headers["Webhook-Signature"] == "v1,Kb+qawXvtjgaYfg4mZ5Nwx56fhXVFDUa+V+BmUirSEY=" &&
            request.headers.keys.none? { |key| key.start_with?("X-Lago") }
        }.once
        expect(webhook).to be_succeeded
      end

      it "loads the signing key once" do
        queries = []
        callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("webhook_endpoint_signing_keys") }

        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { service.call }

        expect(queries.size).to eq(1)
      end

      context "when the endpoint answers with an error" do
        before do
          WebMock.stub_request(:post, "https://wh.test.com").to_return(status: 500, body: "error")
        end

        it "schedules a retry that keeps the id and signs with a new timestamp" do
          service.call

          expect(webhook).to be_retrying
          expect(SendHttpWebhookJob).to have_been_enqueued.with(webhook)

          travel_to(Time.zone.at(1_762_304_400))
          described_class.call(webhook: Webhook.find(webhook.id))

          # Same derivation as above with the timestamp 1762304400.
          expect(WebMock).to have_requested(:post, "https://wh.test.com").with(
            headers: {
              "Webhook-Id" => "8b2f6a1e-3c4d-4e5f-9a6b-7c8d9e0f1a2b",
              "Webhook-Timestamp" => "1762304400",
              "Webhook-Signature" => "v1,mUzwJIALxpDnPZ/2ZjpQp3aqBCSK3/sKsse6S6wfoEM="
            }
          ).once
        end
      end
    end

    context "when the endpoint has no signing key" do
      before do
        WebMock.stub_request(:post, "https://wh.test.com")
      end

      it "fails the webhook without sending it or retrying" do
        result = service.call

        expect(result).to be_success
        expect(WebMock).not_to have_requested(:post, "https://wh.test.com")
        expect(SendHttpWebhookJob).not_to have_been_enqueued
        expect(webhook.reload).to be_failed
        expect(webhook.response).to eq "Webhook endpoint has no signing key"
      end
    end
  end

  context "when client returns an error" do
    let(:error_body) do
      {
        message: "forbidden"
      }
    end
    let(:expected_timeout_seconds) { 30 }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(
          webhook.webhook_endpoint.webhook_url,
          read_timeout: expected_timeout_seconds,
          write_timeout: expected_timeout_seconds,
          open_timeout: expected_timeout_seconds,
          block_private_addresses: true
        )
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response).and_raise(
        LagoHttpClient::HttpError.new(403, error_body.to_json, "")
      )
    end

    context "when LAGO_WEBHOOK_TIMEOUT_SECONDS is set" do
      let(:expected_timeout_seconds) { 45 }

      around do |example|
        original_value = ENV["LAGO_WEBHOOK_TIMEOUT_SECONDS"]
        ENV["LAGO_WEBHOOK_TIMEOUT_SECONDS"] = "45"
        example.run
      ensure
        ENV["LAGO_WEBHOOK_TIMEOUT_SECONDS"] = original_value
      end

      it "uses the configured timeout" do
        service.call

        expect(LagoHttpClient::Client).to have_received(:new)
          .with(
            webhook.webhook_endpoint.webhook_url,
            read_timeout: expected_timeout_seconds,
            write_timeout: expected_timeout_seconds,
            open_timeout: expected_timeout_seconds,
            block_private_addresses: true
          )
      end
    end

    it "creates a retrying webhook" do
      service.call

      expect(webhook).to be_retrying
      expect(webhook.http_status).to eq(403)
      expect(SendHttpWebhookJob).to have_been_enqueued.with(webhook)
    end

    context "with an alert webhook" do
      let(:webhook) { create(:webhook, webhook_endpoint:, webhook_type: "alert.triggered") }

      before { ENV["SIDEKIQ_WEBHOOK"] = "true" }
      after { ENV.delete("SIDEKIQ_WEBHOOK") }

      it "retries on the high priority queue" do
        service.call

        expect(SendHttpWebhookJob).to have_been_enqueued.with(webhook).on_queue("webhook_worker_high_priority")
      end
    end

    context "with a retrying webhook" do
      let(:webhook) { create(:webhook, :retrying, retries: 1) }

      it "fails the retried webhooks" do
        service.call

        expect(webhook).to be_retrying
        expect(webhook.http_status).to eq(403)
        expect(webhook.retries).to eq(2)
        expect(webhook.last_retried_at).not_to be_nil
        expect(SendHttpWebhookJob).to have_been_enqueued.with(webhook)
      end

      context "when the webhook failed 3 times" do
        let(:webhook) { create(:webhook, :retrying, retries: 2) }

        it "stops trying and marks the webhook as failed" do
          service.call

          expect(webhook).to be_failed
          expect(webhook.http_status).to eq(403)
          expect(webhook.reload.retries).to eq 3
          expect(SendHttpWebhookJob).not_to have_been_enqueued
        end
      end
    end
  end

  context "when the response body is larger than the stored limit" do
    before do
      stub_const("#{described_class}::MAX_STORED_RESPONSE_BYTES", 8)
      WebMock.stub_request(:post, "https://wh.test.com").to_return(status: 200, body: "0123456789")
    end

    it "stores a truncated response" do
      service.call

      expect(webhook.response).to eq "01234567"
    end

    context "when the limit cuts a multibyte character" do
      before do
        WebMock.stub_request(:post, "https://wh.test.com").to_return(status: 200, body: "0123456é".b)
      end

      it "drops the partial character" do
        service.call

        expect(webhook).to be_succeeded
        expect(webhook.response).to eq "0123456"
      end
    end
  end

  context "when the response body is not valid UTF-8" do
    before do
      WebMock.stub_request(:post, "https://wh.test.com").to_return(status: 200, body: "ok\xFF".b)
    end

    it "stores the valid part of the response" do
      service.call

      expect(webhook).to be_succeeded
      expect(webhook.response).to eq "ok"
    end
  end

  context "when the connection fails" do
    before do
      WebMock.stub_request(:post, "https://wh.test.com").to_raise(Errno::ECONNREFUSED)
    end

    it "stores a generic message" do
      service.call

      expect(webhook).to be_retrying
      expect(webhook.response).to eq "Connection failed"
    end
  end

  [Errno::ENETUNREACH, Errno::EADDRNOTAVAIL].each do |error_class|
    context "when the connection fails with #{error_class}" do
      before do
        WebMock.stub_request(:post, "https://wh.test.com").to_raise(error_class)
      end

      it "schedules a retry" do
        expect { service.call }.not_to raise_error

        expect(webhook).to be_retrying
        expect(webhook.response).to eq "Connection failed"
        expect(webhook.retries).to eq 1
        expect(SendHttpWebhookJob).to have_been_enqueued.with(webhook)
      end

      context "when it is the last attempt" do
        let(:webhook) { create(:webhook, :retrying, retries: 2, webhook_endpoint:) }

        it "marks the webhook as failed" do
          expect { service.call }.not_to raise_error

          expect(webhook).to be_failed
          expect(webhook.response).to eq "Connection failed"
          expect(webhook.reload.retries).to eq 3
          expect(SendHttpWebhookJob).not_to have_been_enqueued
        end
      end
    end
  end

  context "when the endpoint resolves to a private address" do
    before do
      webhook
      stub_const("ENV", ENV.to_h.merge("LAGO_WEBHOOK_ALLOW_PRIVATE_URLS" => "false"))
      allow(Addrinfo).to receive(:getaddrinfo).and_return([Addrinfo.tcp("169.254.169.254", 0)])
      WebMock.stub_request(:post, "https://wh.test.com")
    end

    it "does not send the webhook" do
      service.call

      expect(WebMock).not_to have_requested(:post, "https://wh.test.com")
      expect(webhook).to be_retrying
      expect(webhook.response).to eq "Destination address is not allowed"
    end
  end

  context "when the first resolved address of a dual-stack endpoint is unreachable" do
    let(:webhook_endpoint) { create(:webhook_endpoint, webhook_url: "http://wh.test.com/hooks") }

    before do
      webhook
      stub_const("ENV", ENV.to_h.merge("LAGO_WEBHOOK_ALLOW_PRIVATE_URLS" => "false"))
      allow(Addrinfo).to receive(:getaddrinfo)
        .and_return([Addrinfo.tcp("2606:4700::6812:11db", 0), Addrinfo.tcp("104.18.17.219", 0)])
      # Plain HTTP connects to the pinned address, so each address has its own URL.
      WebMock.stub_request(:post, "http://[2606:4700::6812:11db]/hooks").to_raise(Errno::ENETUNREACH)
      WebMock.stub_request(:post, "http://104.18.17.219/hooks").to_return(status: 200, body: "ok")
    end

    it "delivers the webhook to the next address" do
      service.call

      expect(WebMock).to have_requested(:post, "http://104.18.17.219/hooks")
        .with(headers: {"Host" => "wh.test.com"}).once
      expect(webhook).to be_succeeded
      expect(webhook.http_status).to eq 200
      expect(webhook.response).to eq "ok"
    end
  end

  context "when no resolved address of a dual-stack endpoint is reachable" do
    let(:webhook_endpoint) { create(:webhook_endpoint, webhook_url: "http://wh.test.com/hooks") }

    before do
      webhook
      stub_const("ENV", ENV.to_h.merge("LAGO_WEBHOOK_ALLOW_PRIVATE_URLS" => "false"))
      allow(Addrinfo).to receive(:getaddrinfo)
        .and_return([Addrinfo.tcp("2606:4700::6812:11db", 0), Addrinfo.tcp("104.18.17.219", 0)])
      WebMock.stub_request(:post, "http://[2606:4700::6812:11db]/hooks").to_raise(Errno::ENETUNREACH)
      WebMock.stub_request(:post, "http://104.18.17.219/hooks").to_raise(Errno::ENETUNREACH)
    end

    it "tries every address then schedules a retry" do
      expect { service.call }.not_to raise_error

      expect(WebMock).to have_requested(:post, "http://[2606:4700::6812:11db]/hooks").once
      expect(WebMock).to have_requested(:post, "http://104.18.17.219/hooks").once
      expect(webhook).to be_retrying
      expect(webhook.response).to eq "Connection failed"
      expect(webhook.retries).to eq 1
      expect(SendHttpWebhookJob).to have_been_enqueued.with(webhook)
    end
  end

  context "when S3 throttles reading the stored payload" do
    let(:webhook) { create(:webhook, :retrying, retries: 1) }
    let(:slow_down_error) { Aws::S3::Errors::SlowDown.new(nil, "Please reduce your request rate.") }

    before do
      allow(webhook).to receive(:payload).and_raise(slow_down_error)
    end

    it "lets the error propagate for the job to retry" do
      expect { service.call }.to raise_error(Aws::S3::Errors::SlowDown)
    end

    it "does not count the S3 error against the webhook retry counter" do
      expect { service.call }.to raise_error(Aws::S3::Errors::SlowDown)

      expect(webhook.retries).to eq(1)
      expect(webhook).to be_retrying
      expect(SendHttpWebhookJob).not_to have_been_enqueued
    end
  end
end
