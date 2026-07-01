# frozen_string_literal: true

require "rails_helper"

describe Clock::CreateIntervalWalletTransactionsJob, job: true do
  subject(:interval_wallet_transactions_job) { described_class }

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
    before { allow(Wallets::CreateIntervalWalletTransactionsService).to receive(:call) }

    it "removes all old webhooks" do
      interval_wallet_transactions_job.perform_now

      expect(Wallets::CreateIntervalWalletTransactionsService).to have_received(:call)
    end
  end
end
