# frozen_string_literal: true

require "rails_helper"

describe WalletTransactions::RecreditJob do
  subject(:perform_job) { described_class.perform_now(wallet_transaction) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:, organization:) }
  let(:wallet_transaction) do
    create(:wallet_transaction, wallet:, organization:, transaction_type: :outbound, invoice:)
  end

  let_it_be(:invoice) { create(:invoice, organization:, customer:) }

  before { allow(WalletTransactions::RecreditService).to receive(:call!) }

  context "when the wallet is active" do
    it "delegates to WalletTransactions::RecreditService" do
      perform_job

      expect(WalletTransactions::RecreditService).to have_received(:call!).with(wallet_transaction:)
    end
  end

  context "when the wallet is terminated" do
    let(:wallet) { create(:wallet, :terminated, customer:, organization:) }

    it "does not call WalletTransactions::RecreditService" do
      perform_job

      expect(WalletTransactions::RecreditService).not_to have_received(:call!)
    end
  end
end
