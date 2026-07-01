# frozen_string_literal: true

require "rails_helper"

describe Clock::TerminateRecurringTransactionRulesJob, job: true do
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

  let(:wallet) { create(:wallet) }
  let(:to_expire_rule) do
    create(
      :recurring_transaction_rule, wallet:,
      status: "active",
      expiration_at: Time.zone.now - 40.days
    )
  end

  let(:to_keep_active_rule) do
    create(
      :recurring_transaction_rule, wallet:,
      status: "active",
      expiration_at: Time.zone.now + 40.days
    )
  end

  before do
    allow(Wallets::RecurringTransactionRules::TerminateService).to receive(:call)
    to_expire_rule
    to_keep_active_rule
  end

  it "terminates expired recurring transaction rules" do
    described_class.perform_now

    expect(Wallets::RecurringTransactionRules::TerminateService)
      .to have_received(:call)
      .with(recurring_transaction_rule: to_expire_rule)

    expect(Wallets::RecurringTransactionRules::TerminateService)
      .not_to have_received(:call)
      .with(recurring_transaction_rule: to_keep_active_rule)
  end
end
