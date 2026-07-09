# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CustomerPortal::WalletTransactions::CreateInput do
  subject { described_class }

  it do
    expect(subject).to accept_argument(:wallet_id).of_type("ID!")
    expect(subject).to accept_argument(:paid_credits).of_type("String")
    expect(subject).to accept_argument(:purchase_order_number).of_type("String")
  end
end
