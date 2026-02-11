# frozen_string_literal: true

require "rails_helper"

describe Clock::ResetSlowWebhookEndpointsJob, job: true do
  subject(:reset_job) { described_class }

  describe ".perform" do
    it "resets slow webhook endpoints" do
      slow_endpoint = create(:webhook_endpoint, slow_response: true)

      reset_job.perform_now

      expect(slow_endpoint.reload.slow_response).to be(false)
    end

    it "does not affect non-slow webhook endpoints" do
      normal_endpoint = create(:webhook_endpoint, slow_response: false)

      reset_job.perform_now

      expect(normal_endpoint.reload.slow_response).to be(false)
    end
  end
end
