# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::SubscriptionsBillerJob do
  subject { described_class }

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
    let(:organization1) { create(:organization, api_keys: []) }
    let(:organization2) { create(:organization, api_keys: []) }

    before do
      organization1
      organization2
    end

    it "enqueues Subscriptions::OrganizationBillingJob for each organization" do
      expect do
        described_class.perform_now
      end.to have_enqueued_job(Subscriptions::OrganizationBillingJob).exactly(2).times
    end
  end
end
