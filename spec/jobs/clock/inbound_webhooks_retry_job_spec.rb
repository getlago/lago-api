# frozen_string_literal: true

require "rails_helper"

describe Clock::InboundWebhooksRetryJob, job: true do
  subject(:inbound_webhooks_retry_job) { described_class }

  describe ".perform" do
    let(:inbound_webhook) { create :inbound_webhook, status:, updated_at: }
    let(:failed_inbound_webhook) { create :inbound_webhook, status: "failed" }
    let(:processing_inbound_webhoook) { create :inbound_webhook, status: "processing" }
    let(:processed_inbound_webhook) { create :inbound_webhook, status: "processed" }

    before { inbound_webhook }

    context "when inbound webhook is pending" do
      let(:status) { "pending" }
      let(:updated_at) { 110.minutes.ago }

      it "does not queue a job" do
        inbound_webhooks_retry_job.perform_now

        expect(InboundWebhooks::ProcessJob).not_to have_been_enqueued
      end

      context "when inbound webhook has not being updated for more than 2 hours" do
        let(:updated_at) { 2.hours.ago }

        it "queues a job to process the failed inbound webhook" do
          inbound_webhooks_retry_job.perform_now

          expect(InboundWebhooks::ProcessJob)
            .to have_been_enqueued
            .with(inbound_webhook: inbound_webhook)
        end
      end
    end

    context "when inbound webhook is processing" do
      let(:status) { "processing" }
      let(:updated_at) { 110.minutes.ago }

      it "does not queue a job" do
        inbound_webhooks_retry_job.perform_now

        expect(InboundWebhooks::ProcessJob).not_to have_been_enqueued
      end

      context "when inbound webhook has not being updated for more than 2 hours" do
        let(:updated_at) { 2.hours.ago }

        it "queues a job to process the failed inbound webhook" do
          inbound_webhooks_retry_job.perform_now

          expect(InboundWebhooks::ProcessJob)
            .to have_been_enqueued
            .with(inbound_webhook: inbound_webhook)
        end
      end
    end

    context "when inbound webhook is failed" do
      let(:status) { "failed" }
      let(:updated_at) { 1.day.ago }

      it "does not queue a job" do
        inbound_webhooks_retry_job.perform_now

        expect(InboundWebhooks::ProcessJob).not_to have_been_enqueued
      end
    end

    context "when inbound webhook is processed" do
      let(:status) { "processed" }
      let(:updated_at) { 1.day.ago }

      it "does not queue a job" do
        inbound_webhooks_retry_job.perform_now

        expect(InboundWebhooks::ProcessJob).not_to have_been_enqueued
      end
    end
  end
end
