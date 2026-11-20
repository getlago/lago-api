# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::ExpirePendingJob do
  subject(:job) { described_class }

  let(:wallet_transaction) { create(:wallet_transaction) }

  before { allow(WalletTransactions::ExpirePendingService).to receive(:call!) }

  it "forwards the wallet transaction to the service" do
    job.perform_now(wallet_transaction)

    expect(WalletTransactions::ExpirePendingService).to have_received(:call!).with(wallet_transaction:)
  end
end
