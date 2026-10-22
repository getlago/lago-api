# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Subscriptions::UsageThresholdsReachedService do
  subject(:webhook_service) { described_class.new(object: subscription, options: {usage_threshold:}) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, plan: plan, customer: customer) }
  let(:usage_threshold) { create(:usage_threshold, plan: plan) }

  describe ".call" do
    it_behaves_like "creates webhook", "subscription.usage_threshold_reached", "subscription", {
      "usage_threshold" => Hash,
      "applicable_usage_thresholds" => Array
    }

    context "when SIDEKIQ_WEBHOOK is true" do
      around do |example|
        original_value = ENV["SIDEKIQ_WEBHOOK"]
        ENV["SIDEKIQ_WEBHOOK"] = "true"
        example.run
      ensure
        ENV["SIDEKIQ_WEBHOOK"] = original_value
      end

      it "enqueues the http job on the high priority queue" do
        webhook_service.call

        expect(SendHttpWebhookJob).to have_been_enqueued.on_queue("webhook_worker_high_priority")
      end
    end
  end
end
