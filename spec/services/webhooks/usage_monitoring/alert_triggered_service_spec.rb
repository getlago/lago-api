# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::UsageMonitoring::AlertTriggeredService do
  subject(:webhook_service) { described_class.new(object: triggered_alert) }

  let(:triggered_alert) { create(:triggered_alert) }

  describe ".call" do
    it_behaves_like "creates webhook", "alert.triggered", "triggered_alert"

    context "when SIDEKIQ_WEBHOOK is true" do
      before { ENV["SIDEKIQ_WEBHOOK"] = "true" }
      after { ENV.delete("SIDEKIQ_WEBHOOK") }

      it "enqueues the http job on the high priority queue" do
        webhook_service.call

        expect(SendHttpWebhookJob).to have_been_enqueued.on_queue("webhook_worker_high_priority")
      end
    end
  end
end
