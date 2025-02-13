# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Wallets::RecurringTransactionRules::UpdateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:interval).of_type("RecurringTransactionIntervalEnum")
    expect(subject).to accept_argument(:method).of_type("RecurringTransactionMethodEnum")
    expect(subject).to accept_argument(:started_at).of_type("ISO8601DateTime")
    expect(subject).to accept_argument(:target_ongoing_balance).of_type("String")
    expect(subject).to accept_argument(:trigger).of_type("RecurringTransactionTriggerEnum")
    expect(subject).to accept_argument(:threshold_credits).of_type("String")
    expect(subject).to accept_argument(:lago_id).of_type("ID")
    expect(subject).to accept_argument(:paid_credits).of_type("String")
    expect(subject).to accept_argument(:granted_credits).of_type("String")
  end
end
