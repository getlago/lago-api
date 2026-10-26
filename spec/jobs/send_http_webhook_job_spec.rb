# frozen_string_literal: true

require "rails_helper"
require "aws-sdk-s3"

RSpec.describe SendHttpWebhookJob do
  before_all do
    create_default(:organization)
    create_default(:customer)
    create_default(:invoice)
  end

  subject(:send_http_webhook_job) { described_class }

  let(:webhook) { create(:webhook) }

  describe "queue" do
    it_behaves_like "a configurable queue", "webhook_worker", "SIDEKIQ_WEBHOOK", "webhook" do
      let(:arguments) { webhook }
    end

    context "with an alert webhook" do
      it_behaves_like "a configurable queue", "webhook_worker_high_priority", "SIDEKIQ_WEBHOOK", "webhook" do
        let(:arguments) { create(:webhook, webhook_type: "alert.triggered") }
      end

      it_behaves_like "a configurable queue", "webhook_alert_worker", "SIDEKIQ_WEBHOOK_ALERT", "webhook" do
        let(:arguments) { create(:webhook, webhook_type: "alert.triggered") }
      end
    end
  end

  describe "#perform" do
    before { allow(Webhooks::SendHttpService).to receive(:call) }

    it "calls the send http webhook service" do
      send_http_webhook_job.perform_now(webhook)

      expect(Webhooks::SendHttpService).to have_received(:call).with(webhook:)
    end

    context "when S3 throttles the payload storage" do
      let(:slow_down_error) { Aws::S3::Errors::SlowDown.new(nil, "Please reduce your request rate.") }

      before { allow(Webhooks::SendHttpService).to receive(:call).and_raise(slow_down_error) }

      it "retries the job instead of failing" do
        expect { send_http_webhook_job.perform_now(webhook) }
          .to have_enqueued_job(described_class).with(webhook)
      end

      it "does not increment the webhook retries counter" do
        expect { send_http_webhook_job.perform_now(webhook) }
          .not_to change { webhook.reload.retries }
      end
    end
  end
end
