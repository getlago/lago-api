# frozen_string_literal: true

require "rails_helper"

describe Clock::WebhooksCleanupJob, job: true do
  subject(:webhooks_cleanup_job) { described_class }

  describe ".perform" do
    it "removes all old webhooks" do
      create(:webhook, :succeeded, updated_at: 100.days.ago)

      expect { webhooks_cleanup_job.perform_now }
        .to change(Webhook, :count).to(0)
    end

    it "does not delete recent webhooks" do
      create(:webhook, updated_at: 89.days.ago)

      expect { webhooks_cleanup_job.perform_now }
        .not_to change(Webhook, :count)
    end
  end
end
