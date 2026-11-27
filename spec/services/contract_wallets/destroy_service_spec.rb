# frozen_string_literal: true

require "rails_helper"

describe ContractWallets::DestroyService do
  subject(:result) { described_class.call(contract_wallet:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }

  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents:) }
  let(:balance_cents) { 0 }

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  it "soft deletes the wallet" do
    expect(result).to be_success
    expect(result.contract_wallet).to be_discarded
    expect(contract.wallets.reload).to be_empty
  end

  it "logs the deletion" do
    result

    expect(Utils::ActivityLog).to have_received(:produce).with(contract_wallet, "contract_wallet.deleted", after_commit: true)
  end

  it "locks the contract without holding back the rows that reference it" do
    statements = capture_sql { result }

    expect(statements).to include(a_string_matching(/FROM "contracts".*FOR NO KEY UPDATE/))
  end

  context "when the wallet has taxes, a scope and spent credit" do
    let(:applied_tax) { create(:catalog_wallet_applied_tax, organization:, catalog_wallet: contract_wallet) }
    let(:selector) { create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet) }
    let(:spent_entry) { create(:catalog_wallet_transaction, organization:, catalog_wallet: contract_wallet, remaining_credit_amount_cents: 0) }

    before do
      applied_tax
      selector
      spent_entry
    end

    it "soft deletes the wallet and keeps them" do
      expect(result).to be_success
      expect(result.contract_wallet).to be_discarded
      expect(result.contract_wallet.applied_taxes).to eq([applied_tax])
      expect(result.contract_wallet.selectors).to eq([selector])
      expect(result.contract_wallet.transactions).to eq([spent_entry])
    end
  end

  context "when the contract has ended since the wallet was loaded" do
    before do
      contract_wallet
      Contract.find(contract.id).update!(status: :terminated, terminated_at: Time.current)
    end

    it "refuses it and keeps the wallet" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("contract_not_live")
      expect(contract_wallet.reload).to be_kept
    end
  end

  context "when the wallet has alerts" do
    let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: contract_wallet) }
    let(:other_alert) { create(:catalog_wallet_alert, organization:) }

    before do
      alert
      other_alert
    end

    it "deletes them with the wallet and leaves the alerts of other wallets" do
      expect(result).to be_success
      expect(UsageMonitoring::CatalogWalletAlert.where(id: [alert.id, other_alert.id])).to eq([other_alert])
    end

    context "when the wallet holds credit" do
      let(:balance_cents) { 1 }

      it "refuses it and keeps them" do
        expect(result.error.code).to eq("wallet_holds_credit")
        expect(UsageMonitoring::CatalogWalletAlert.where(id: [alert.id, other_alert.id]).count).to eq(2)
      end
    end
  end

  context "when the wallet has been credited since it was loaded" do
    before do
      contract_wallet
      CatalogWallet.find(contract_wallet.id).update!(balance_cents: 1)
    end

    it "refuses it and keeps the wallet" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("wallet_holds_credit")
      expect(contract_wallet.reload).to be_kept
    end
  end

  context "when the wallet holds credit" do
    let(:balance_cents) { 1 }

    it "refuses it and keeps the wallet" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("wallet_holds_credit")
      expect(contract_wallet.reload).to be_kept
    end
  end

  context "when credit bought for the wallet is waiting for its payment" do
    before { create(:catalog_wallet_transaction, :pending, organization:, catalog_wallet: contract_wallet) }

    it "refuses it and keeps the wallet" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("wallet_holds_credit")
      expect(contract_wallet.reload).to be_kept
    end
  end

  context "when a pending entry takes credit out of the wallet" do
    before { create(:catalog_wallet_transaction, :pending, :invoice_application, organization:, catalog_wallet: contract_wallet) }

    it "soft deletes the wallet" do
      expect(result).to be_success
      expect(result.contract_wallet).to be_discarded
    end
  end

  context "when a purchase for the wallet has failed" do
    before { create(:catalog_wallet_transaction, :failed, organization:, catalog_wallet: contract_wallet) }

    it "refuses it and keeps the wallet" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("wallet_holds_credit")
      expect(contract_wallet.reload).to be_kept
    end
  end

  context "when the wallet has a credit allocation" do
    let(:credit_allocation) { create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: contract_wallet, deleted_at:) }
    let(:deleted_at) { nil }

    before { credit_allocation }

    it "refuses it and keeps both" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq("wallet_has_credit_allocations")
      expect(contract_wallet.reload).to be_kept
      expect(credit_allocation.reload).to be_kept
    end

    context "when the credit allocation is deleted" do
      let(:deleted_at) { Time.current }

      it "soft deletes the wallet" do
        expect(result).to be_success
        expect(result.contract_wallet).to be_discarded
      end
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:) }

    it "soft deletes the wallet" do
      expect(result).to be_success
      expect(result.contract_wallet).to be_discarded
    end
  end

  [:terminated, :canceled].each do |status|
    context "when the contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:) }

      it "refuses it and keeps the wallet" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("contract_not_live")
        expect(contract_wallet.reload).to be_kept
      end
    end
  end

  context "when the wallet does not exist" do
    let(:contract_wallet) { nil }

    it "returns a contract wallet not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("contract_wallet")
    end
  end

  context "when another request has deleted the wallet" do
    subject(:result) { described_class.call(contract_wallet: stale_contract_wallet) }

    let(:stale_contract_wallet) { CatalogWallet.find(contract_wallet.id) }

    before do
      stale_contract_wallet
      contract_wallet.discard!
    end

    it "returns a contract wallet not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("contract_wallet")
    end
  end
end
