# frozen_string_literal: true

require "rails_helper"

describe PlanWallets::DestroyService do
  subject(:result) { described_class.call(plan_wallet:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:) }

  let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:) }

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  it "soft deletes the wallet template" do
    expect(result).to be_success
    expect(result.plan_wallet).to be_discarded
    expect(catalog_plan.wallets.reload).to be_empty
  end

  it "logs the deletion" do
    result

    expect(Utils::ActivityLog).to have_received(:produce).with(plan_wallet, "plan_wallet.deleted", after_commit: true)
  end

  context "when the wallet template has credit allocations, taxes and a scope" do
    let(:credit_allocation) { create(:plan_wallet_credit_allocation, organization:, plan_wallet:) }
    let(:applied_tax) { create(:catalog_wallet_applied_tax, :plan_level, organization:, plan_wallet:) }
    let(:selector) { create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:) }

    before do
      credit_allocation
      applied_tax
      selector
    end

    it "soft deletes the credit allocations and keeps the taxes and the scope" do
      freeze_time do
        expect(result).to be_success
        expect(PlanWalletCreditAllocation.with_discarded.find(credit_allocation.id))
          .to have_attributes(deleted_at: Time.current, updated_at: Time.current)
        expect(result.plan_wallet.applied_taxes).to eq([applied_tax])
        expect(result.plan_wallet.selectors).to eq([selector])
      end
    end
  end

  context "when the plan has contracts" do
    before { create(:contract, organization:, catalog_plan:) }

    it "still deletes the wallet template" do
      expect(result).to be_success
      expect(result.plan_wallet).to be_discarded
    end
  end

  context "when the wallet template does not exist" do
    let(:plan_wallet) { nil }

    it "returns a wallet not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("wallet")
    end
  end

  context "when another request has already deleted it" do
    subject(:result) { described_class.call(plan_wallet: stale_plan_wallet) }

    let(:stale_plan_wallet) { PlanWallet.find(plan_wallet.id) }

    before do
      stale_plan_wallet
      described_class.call!(plan_wallet:)
    end

    it "returns a wallet not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("wallet")
    end
  end
end
