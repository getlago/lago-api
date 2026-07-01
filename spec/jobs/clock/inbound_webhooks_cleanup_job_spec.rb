# frozen_string_literal: true

require "rails_helper"

describe Clock::InboundWebhooksCleanupJob, job: true do
  subject(:inbound_webhooks_cleanup_job) { described_class }

  describe "unique job behavior" do
    around do |example|
      ActiveJob::Uniqueness.reset_manager!
      example.run
      ActiveJob::Uniqueness.test_mode!
    end

    it "does not enqueue duplicate jobs" do
      expect do
        described_class.perform_later
        described_class.perform_later
      end.to change { enqueued_jobs.count }.by(1) # rubocop:disable RSpec/ExpectChange
    end
  end

  describe ".perform" do
    it "removes all old inbound webhooks" do
      create(:inbound_webhook, updated_at: 90.days.ago)

      expect { inbound_webhooks_cleanup_job.perform_now }
        .to change(InboundWebhook, :count).to(0)
    end

    it "does not delete recent inbound webhooks" do
      create(:inbound_webhook, updated_at: 89.days.ago)

      expect { inbound_webhooks_cleanup_job.perform_now }
        .not_to change(InboundWebhook, :count)
    end
  end
end
