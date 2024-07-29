# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::WalletTransactions::Object do
  subject { described_class }

  it { is_expected.to have_field(:wallet).of_type('Wallet') }

  it { is_expected.to have_field(:amount).of_type('String!') }
  it { is_expected.to have_field(:credit_amount).of_type('String!') }
  it { is_expected.to have_field(:invoice_requires_successful_payment).of_type('Boolean!') }
  it { is_expected.to have_field(:status).of_type('WalletTransactionStatusEnum!') }
  it { is_expected.to have_field(:transaction_status).of_type('WalletTransactionTransactionStatusEnum!') }
  it { is_expected.to have_field(:transaction_type).of_type('WalletTransactionTransactionTypeEnum!') }

  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:settled_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }
end
