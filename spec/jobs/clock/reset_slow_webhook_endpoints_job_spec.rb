# frozen_string_literal: true

require "rails_helper"

describe Clock::ResetSlowWebhookEndpointsJob, job: true do
  subject(:reset_job) { described_class }

  describe ".perform" do
    let(:endpoint) { create(:webhook_endpoint, slow_response:) }
    let(:slow_response) { true }

    before { endpoint }

    it "resets slow webhook endpoints" do
      reset_job.perform_now

      expect(endpoint.reload.slow_response).to be(false)
    end

    context "when endpoint is not slow" do
      let(:slow_response) { false }

      it "does not affect non-slow webhook endpoints" do
        reset_job.perform_now

        expect(endpoint.reload.slow_response).to be(false)
      end
    end
  end
end
