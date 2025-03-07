# frozen_string_literal: true

require "rails_helper"

describe Clock::TerminateRecurringTransactionRulesJob, job: true do
  let(:wallet) { create(:wallet) }
  let(:to_expire_rule) do
    create(
      :recurring_transaction_rule,
      status: "active",
      expiration_at: Time.zone.now - 40.days,
      wallet:
    )
  end

  let(:to_keep_active_rule) do
    create(
      :recurring_transaction_rule,
      status: "active",
      expiration_at: Time.zone.now + 40.days,
      wallet:
    )
  end

  before do
    allow(Wallets::RecurringTransactionRules::TerminateService)
      .to receive(:call).and_call_original

    to_expire_rule
    to_keep_active_rule
  end

  it "terminates the expired recurring transaction rules" do
    described_class.perform_now

    expect(Wallets::RecurringTransactionRules::TerminateService)
      .to have_received(:call).with(recurring_transaction_rule: to_expire_rule)

    expect(to_expire_rule.reload.status).to eq("terminated")
    expect(to_keep_active_rule.reload.status).to eq("active")
  end
end
