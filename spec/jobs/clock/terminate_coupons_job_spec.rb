# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::TerminateCouponsJob do
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
    before { allow(Coupons::TerminateService).to receive(:terminate_all_expired) }

    it "calls Coupons::TerminateService.terminate_all_expired" do
      described_class.perform_now

      expect(Coupons::TerminateService).to have_received(:terminate_all_expired)
    end
  end
end
