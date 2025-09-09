# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Wallets::CreateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:currency).of_type("CurrencyEnum!")
    expect(subject).to accept_argument(:customer_id).of_type("ID!")
    expect(subject).to accept_argument(:expiration_at).of_type("ISO8601DateTime")
    expect(subject).to accept_argument(:granted_credits).of_type("String!")
    expect(subject).to accept_argument(:invoice_requires_successful_payment).of_type("Boolean")
    expect(subject).to accept_argument(:name).of_type("String")
    expect(subject).to accept_argument(:paid_credits).of_type("String!")
    expect(subject).to accept_argument(:rate_amount).of_type("String!")

    expect(subject).to accept_argument(:paid_top_up_max_amount_cents).of_type("BigInt")
    expect(subject).to accept_argument(:paid_top_up_min_amount_cents).of_type("BigInt")

    expect(subject).to accept_argument(:recurring_transaction_rules).of_type("[CreateRecurringTransactionRuleInput!]")

    expect(subject).to accept_argument(:applies_to).of_type("AppliesToInput")
  end
end
