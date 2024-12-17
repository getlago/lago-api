# frozen_string_literal: true

require 'rails_helper'

describe Clock::InboundWebhooksRetryJob, job: true do
  subject(:inbound_webhooks_retry_job) { described_class }

  describe '.perform' do
    let(:pending_inbound_webhook) { create :inbound_webhook, status: "pending" }
    let(:failed_inbound_webhook) { create :inbound_webhook, status: "failed" }
    let(:processing_inbound_webhoook) { create :inbound_webhook, status: "processing" }
    let(:processed_inbound_webhook) { create :inbound_webhook, status: "processed" }

    before do
      pending_inbound_webhook
      failed_inbound_webhook
      processed_inbound_webhook
      processed_inbound_webhook
    end

    it "queues a job to process the failed inbound webhook" do
      inbound_webhooks_retry_job.perform_now

      expect(InboundWebhooks::ProcessJob).to have_been_enqueued.once
      expect(InboundWebhooks::ProcessJob)
        .to have_been_enqueued
        .with(inbound_webhook: failed_inbound_webhook)
    end
  end
end
