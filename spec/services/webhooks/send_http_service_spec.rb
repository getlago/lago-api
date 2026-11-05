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
    let(:webhook_endpoint) do
      create(
        :webhook_endpoint,
        organization: create(:organization, feature_flags: ["standard_webhooks_signature"]),
        webhook_url: "https://wh.test.com",
        signature_algo: :standard_webhooks
      )
    end
    let(:secret) { "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw" }
    let(:expires_at) { nil }
    let(:posted_requests) { [] }

    before do
      create(:webhook_endpoint_signing_key, webhook_endpoint:, secret_key: secret, expires_at:)
      WebMock.stub_request(:post, "https://wh.test.com").to_return do |request|
        posted_requests << request
        {status: 200, body: "ok"}
      end
    end

    it "signs the exact posted body with the Standard Webhooks headers" do
      freeze_time do
        service.call

        request = posted_requests.sole
        headers = request.headers.transform_keys(&:downcase)
        # Standard Webhooks reference: base64(HMAC-SHA256(decoded secret, "{webhook-id}.{webhook-timestamp}.{raw body}"))
        key = Base64.strict_decode64(secret.delete_prefix("whsec_"))
        signed_content = "#{headers["webhook-id"]}.#{headers["webhook-timestamp"]}.#{request.body}"

        expect(headers["webhook-signature"]).to eq("v1," + Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, signed_content)))
        expect(headers["webhook-id"]).to eq(webhook.id)
        expect(headers["webhook-timestamp"]).to eq(Time.current.to_i.to_s)
        expect(headers.keys.grep(/\Ax-lago-/)).to be_empty
        expect(webhook.reload).to be_succeeded
      end
    end

    context "when a failed delivery is retried" do
      let(:t1) { Time.zone.parse("2026-11-03T10:00:00Z") }
      let(:statuses) { [500, 200] }

      before do
        WebMock.stub_request(:post, "https://wh.test.com").to_return do |request|
          posted_requests << request
          {status: statuses.shift, body: "ok"}
        end
      end

      it "keeps the webhook-id and signs each attempt with its own timestamp" do
        travel_to(t1) { described_class.new(webhook:).call }
        travel_to(t1 + 5.minutes) { described_class.new(webhook: webhook.reload).call }

        first, second = posted_requests.map { |request| request.headers.transform_keys(&:downcase) }
        expect([first["webhook-id"], second["webhook-id"]]).to eq([webhook.id, webhook.id])
        expect(first["webhook-timestamp"]).to eq(t1.to_i.to_s)
        expect(second["webhook-timestamp"]).to eq((t1 + 5.minutes).to_i.to_s)
        expect(first["webhook-signature"]).not_to eq(second["webhook-signature"])
        expect(webhook.reload).to be_succeeded
      end
    end

    context "when the endpoint has no usable key" do
      let(:expires_at) { 1.minute.ago }

      it "raises and sends nothing" do
        expect { service.call }.to raise_error(Webhook::MissingSigningKeyError)

        expect(a_request(:post, "https://wh.test.com")).not_to have_been_made
        expect(webhook.reload).to be_pending
        expect(SendHttpWebhookJob).not_to have_been_enqueued
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
