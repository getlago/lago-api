# frozen_string_literal: true

require "rails_helper"

describe Contracts::MaterializeWalletsService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

  let(:settings) do
    {
      code: "ai_credits",
      name: "AI credits",
      invoice_display_name: "Credits",
      currency: "USD",
      tax_application: "tax_on_purchase",
      priority: 10,
      top_up_min_amount_cents: 1_000,
      top_up_max_amount_cents: 50_000
    }
  end
  let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, **settings) }

  before { plan_wallet }

  it "gives the contract a wallet with the template's settings" do
    expect { result }.to change(CatalogWallet, :count).by(1)

    wallet = contract.wallets.sole
    expect(wallet).to have_attributes(organization:, customer:, balance_cents: 0, ongoing_balance_cents: 0, **settings)
    expect(result.wallets).to eq([wallet])
  end

  it "locks the wallet's currency" do
    wallet = result.wallets.sole

    expect { wallet.update!(currency: "EUR") }.to raise_error(ActiveRecord::ReadonlyAttributeError)
  end

  it "locks the wallet's tax application" do
    wallet = result.wallets.sole

    expect { wallet.update!(tax_application: "tax_on_consumption") }.to raise_error(ActiveRecord::ReadonlyAttributeError)
  end

  it "leaves the template untouched" do
    expect { result }.not_to change { plan_wallet.reload.attributes }
  end

  context "when the template has a scope" do
    let(:product) { create(:product, organization:) }

    before do
      create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:)
      create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product", fee_type: nil, product:, with_product_filters: true)
    end

    it "copies each selector onto the contract's wallet" do
      expect { result }.to change(CatalogWalletSelector, :count).by(2)

      selectors = result.wallets.sole.selectors
      expect(selectors.map { [it.organization, it.selector_type, it.fee_type, it.product, it.with_product_filters] })
        .to contain_exactly([organization, "fee_type", "metered", nil, false], [organization, "product", nil, product, true])
      expect(selectors.map(&:plan_wallet_id)).to all(be_nil)
    end

    it "keeps the template's own selectors" do
      result

      expect(plan_wallet.selectors.count).to eq(2)
    end
  end

  context "when the template has taxes" do
    let(:tax) { create(:tax, organization:) }

    before { create(:catalog_wallet_applied_tax, :plan_level, organization:, plan_wallet:, tax:) }

    it "applies them to the contract's wallet" do
      expect { result }.to change(CatalogWalletAppliedTax, :count).by(1)

      expect(result.wallets.sole.applied_taxes.sole).to have_attributes(organization:, tax:, plan_wallet_id: nil)
    end

    it "keeps the template's own taxes" do
      result

      expect(plan_wallet.taxes).to eq([tax])
    end
  end

  context "when the template has credit allocation rules" do
    let(:product) { create(:product, organization:) }

    before do
      create(:plan_wallet_credit_allocation, organization:, plan_wallet:, product:, code: "monthly_allowance", billing_cycles: 3, credit_amount_cents: 10_000, priority: 10)
      create(
        :plan_wallet_credit_allocation,
        :ongoing_balance,
        organization:,
        plan_wallet:,
        code: "auto_top_up",
        threshold_amount_cents: 2_000,
        credit_amount_cents: 10_000,
        purchase_amount_cents: 8_000,
        priority: 20,
        invoice_requires_successful_payment: false
      )
    end

    it "copies each rule onto the contract's wallet" do
      expect { result }.to change(CatalogWalletCreditAllocation, :count).by(2)

      allocations = result.wallets.sole.credit_allocations.index_by(&:code)
      expect(allocations.fetch("monthly_allowance")).to have_attributes(
        organization:,
        trigger: "billing_cycle",
        product:,
        product_filter: nil,
        billing_cycles: 3,
        credit_amount_cents: 10_000,
        priority: 10,
        threshold_amount_cents: nil,
        purchase_amount_cents: nil,
        invoice_requires_successful_payment: nil
      )
      expect(allocations.fetch("auto_top_up")).to have_attributes(
        organization:,
        trigger: "ongoing_balance",
        product: nil,
        product_filter: nil,
        billing_cycles: nil,
        credit_amount_cents: 10_000,
        priority: 20,
        threshold_amount_cents: 2_000,
        purchase_amount_cents: 8_000,
        invoice_requires_successful_payment: false
      )
    end

    it "grants no credit" do
      expect { result }.not_to change(CatalogWalletTransaction, :count)
    end

    context "when a rule was deleted from the template" do
      before { create(:plan_wallet_credit_allocation, organization:, plan_wallet:, code: "welcome_bonus", deleted_at: Time.current) }

      it "does not copy it" do
        expect(result.wallets.sole.credit_allocations.map(&:code)).to contain_exactly("monthly_allowance", "auto_top_up")
      end
    end
  end

  context "when the template has metadata" do
    let(:metadata) { create(:item_metadata, organization:, owner: plan_wallet, value: {"tier" => "gold"}) }

    before { metadata }

    it "gives the contract's wallet its own copy" do
      expect { result }.to change(Metadata::ItemMetadata, :count).by(1)

      expect(result.wallets.sole.metadata).to have_attributes(organization:, value: {"tier" => "gold"})
      expect(plan_wallet.reload.metadata).to eq(metadata)
    end
  end

  context "when the plan has several templates" do
    before do
      create(:plan_wallet, organization:, catalog_plan:, code: "support_credits", currency: "USD")
      create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:)
    end

    it "gives the contract one wallet per template" do
      expect(result.wallets.map(&:code)).to contain_exactly("ai_credits", "support_credits")
    end

    it "copies each template's scope onto its own wallet" do
      wallets = result.wallets.index_by(&:code)

      expect(wallets.fetch("ai_credits").selectors.count).to eq(1)
      expect(wallets.fetch("support_credits").selectors).to be_empty
    end
  end

  context "when another contract already has the plan's wallets" do
    let(:other_contract) { create(:contract, organization:, customer:, catalog_plan:) }

    before { described_class.call!(contract: other_contract) }

    it "gives each contract its own wallet" do
      expect { result }.to change(CatalogWallet, :count).by(1)

      expect(contract.wallets.sole).not_to eq(other_contract.wallets.sole)
    end
  end

  context "when a template was deleted from the plan" do
    let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, deleted_at: Time.current) }

    it "does not copy it" do
      expect { result }.not_to change(CatalogWallet, :count)
      expect(result.wallets).to be_empty
    end
  end

  context "when the plan has no template" do
    let(:plan_wallet) { nil }

    it "creates no wallet" do
      expect { result }.not_to change(CatalogWallet, :count)
      expect(result.wallets).to be_empty
    end
  end

  context "when the contract has no plan" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan: nil) }

    it "creates no wallet" do
      expect { result }.not_to change(CatalogWallet, :count)
      expect(result.wallets).to be_nil
    end
  end
end
