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

      context "when there are pending webhooks for non-slow endpoints" do
        before do
          non_slow_endpoint = create(:webhook_endpoint, organization: webhook_endpoint.organization)
          create(:webhook, :pending, webhook_endpoint: non_slow_endpoint)
        end

        it "re-enqueues the job and does not process the webhook" do
          allow(described_class).to receive(:perform_later)
          allow(Webhooks::SendHttpService).to receive(:call)

          job.perform(webhook)

          expect(described_class).to have_received(:perform_later).with(webhook)
          expect(Webhooks::SendHttpService).not_to have_received(:call)
        end
      end

      context "when there are no pending webhooks for non-slow endpoints" do
        it "processes the webhook normally" do
          allow(Webhooks::SendHttpService).to receive(:call)

          job.perform(webhook)

          expect(Webhooks::SendHttpService).to have_received(:call).with(webhook:)
        end
      end
    end
  end
end
