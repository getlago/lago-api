# frozen_string_literal: true

require "rails_helper"

describe SendHttpWebhookJob, job: true do
  subject(:job) { described_class.new }

  let(:webhook_endpoint) { create(:webhook_endpoint, slow_response:) }
  let(:webhook) { create(:webhook, webhook_endpoint:) }
  let(:slow_response) { false }

  describe "#perform" do
    context "when the endpoint is not slow" do
      it "processes the webhook" do
        allow(Webhooks::SendHttpService).to receive(:call)

        job.perform(webhook)

        expect(Webhooks::SendHttpService).to have_received(:call).with(webhook:)
      end
    end

    context "when the endpoint is slow" do
      let(:slow_response) { true }

      it "enqueues a SendSlowHttpWebhookJob and does not process the webhook" do
        allow(SendSlowHttpWebhookJob).to receive(:perform_later)
        allow(Webhooks::SendHttpService).to receive(:call)

        job.perform(webhook)

        expect(SendSlowHttpWebhookJob).to have_received(:perform_later).with(webhook)
        expect(Webhooks::SendHttpService).not_to have_received(:call)
      end
    end
  end
end
