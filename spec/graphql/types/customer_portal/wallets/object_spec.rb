# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CustomerPortal::Wallets::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type("ID!") }

  it { is_expected.to have_field(:currency).of_type("CurrencyEnum!") }
  it { is_expected.to have_field(:expiration_at).of_type("ISO8601DateTime") }
  it { is_expected.to have_field(:name).of_type("String") }
  it { is_expected.to have_field(:status).of_type("WalletStatusEnum!") }

  it { is_expected.to have_field(:balance_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:consumed_amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:consumed_credits).of_type("Float!") }
  it { is_expected.to have_field(:credits_balance).of_type("Float!") }
  it { is_expected.to have_field(:credits_ongoing_balance).of_type("Float!") }
  it { is_expected.to have_field(:ongoing_balance_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:ongoing_usage_balance_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:rate_amount).of_type("Float!") }
end
