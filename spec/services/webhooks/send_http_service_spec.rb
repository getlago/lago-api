# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::SendHttpService do
  subject(:service) { described_class.new(webhook:) }

  let(:webhook_endpoint) { create(:webhook_endpoint, webhook_url: "https://wh.test.com") }
  let(:webhook) { create(:webhook, webhook_endpoint:) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }

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
    end
  end

  context "when client returns an error" do
    let(:error_body) do
      {
        message: "forbidden"
      }
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new).with(webhook.webhook_endpoint.webhook_url, write_timeout: 30).and_return(lago_client)
      allow(lago_client).to receive(:post_with_response).and_raise(
        LagoHttpClient::HttpError.new(403, error_body.to_json, "")
      )
      allow(SendHttpWebhookJob).to receive(:set).and_return(class_double(SendHttpWebhookJob, perform_later: nil))
    end

    it "creates a failed webhook" do
      service.call

      expect(webhook).to be_failed
      expect(webhook.http_status).to eq(403)
      expect(SendHttpWebhookJob).to have_received(:set)
    end

    context "with a failed webhook" do
      let(:webhook) { create(:webhook, :failed) }

      it "fails the retried webhooks" do
        service.call

        expect(webhook).to be_failed
        expect(webhook.http_status).to eq(403)
        expect(webhook.retries).to eq(1)
        expect(webhook.last_retried_at).not_to be_nil
        expect(SendHttpWebhookJob).to have_received(:set)
      end

      context "when the webhook failed 3 times" do
        let(:webhook) { create(:webhook, :failed, retries: 2) }

        it "stops trying and notify the admins" do
          service.call
          expect(webhook.reload.retries).to eq 3
          expect(SendHttpWebhookJob).not_to have_received(:set)
        end
      end
    end
  end
end
