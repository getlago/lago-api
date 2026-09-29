# frozen_string_literal: true

require "rails_helper"
require "aws-sdk-s3"

RSpec.describe Webhooks::SendHttpService do
  subject(:service) { described_class.new(webhook:) }

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
