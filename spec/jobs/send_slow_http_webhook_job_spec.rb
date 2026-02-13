# frozen_string_literal: true

require "rails_helper"

describe SendSlowHttpWebhookJob, job: true do
  subject(:job) { described_class.new }

  let(:webhook_endpoint) { create(:webhook_endpoint, slow_response: true) }
  let(:webhook) { create(:webhook, webhook_endpoint:) }

  describe "#perform" do
    it "processes the webhook" do
      allow(Webhooks::SendHttpService).to receive(:call)

      job.perform(webhook)

      expect(Webhooks::SendHttpService).to have_received(:call).with(webhook:)
    end
  end
end
