# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Wallets::RecurringTransactionRules::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:lago_id).of_type("ID!")
    expect(subject).to have_field(:method).of_type("RecurringTransactionMethodEnum!")
    expect(subject).to have_field(:trigger).of_type("RecurringTransactionTriggerEnum!")
    expect(subject).to have_field(:interval).of_type("RecurringTransactionIntervalEnum")

    expect(subject).to have_field(:started_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:target_ongoing_balance).of_type("String")
    expect(subject).to have_field(:threshold_credits).of_type("String")
    expect(subject).to have_field(:paid_credits).of_type("String!")
    expect(subject).to have_field(:granted_credits).of_type("String!")

    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
  end
end
