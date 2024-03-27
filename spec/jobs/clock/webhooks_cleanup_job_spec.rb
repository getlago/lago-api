# frozen_string_literal: true

require "rails_helper"

describe Clock::WebhooksCleanupJob, job: true do
  subject(:webhooks_cleanup_job) { described_class }

  describe ".perform" do
    before do
      create(:webhook, :succeeded, updated_at: 100.days.ago)
    end

    it "removes all old webhooks" do
      webhooks_cleanup_job.perform_now

      expect(Webhook.all.count).to be_zero
    end
  end
end
