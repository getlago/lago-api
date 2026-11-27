# frozen_string_literal: true

require "rails_helper"

describe Invoices::CreateCreditPurchaseService do
  subject(:result) { described_class.call(wallet_transaction:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
  let(:contract) { create(:contract, organization:, customer:, purchase_order_number: "PO-1") }
  let(:tax_application) { "tax_on_purchase" }
  let(:wallet) { create(:catalog_wallet, organization:, customer:, contract:, tax_application:, balance_cents: 5_000) }
  let(:wallet_transaction) do
    create(
      :catalog_wallet_transaction,
      :pending,
      organization:,
      catalog_wallet: wallet,
      purchase_amount_cents: 8_000,
      credit_amount_cents: 10_000
    )
  end
  let(:tax) { create(:tax, organization:, rate: 20) }

  shared_examples "an untaxed hidden purchase" do
    it "builds the invoice open with no tax" do
      expect { result }.not_to have_enqueued_job(Invoices::ProviderTaxes::PullTaxesAndApplyJob)

      expect(result).to be_success
      expect(result.invoice).to have_attributes(
        status: "open",
        tax_status: nil,
        fees_amount_cents: 8_000,
        taxes_amount_cents: 0,
        sub_total_excluding_taxes_amount_cents: 8_000,
        sub_total_including_taxes_amount_cents: 8_000,
        total_amount_cents: 8_000
      )
      expect(result.invoice.applied_taxes).to be_empty
      expect(result.fee.applied_taxes).to be_empty
      expect(result.fee.taxes_amount_cents).to eq(0)
    end
  end

  shared_examples "a refused entry" do |code|
    before { wallet_transaction }

    it "writes nothing" do
      expect { result }
        .to not_change(Invoice, :count)
        .and not_change(Fee, :count)
        .and not_change { wallet_transaction.reload.invoice_id }

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
      expect(result.error.code).to eq(code)
    end
  end

  it "builds a hidden purchase invoice on the customer's billing entity" do
    # 02:00 UTC on 16 March is 22:00 on 15 March in New York
    travel_to(Time.utc(2026, 3, 16, 2)) do
      expect { result }.to change(Invoice, :count).by(1).and change(Fee, :count).by(1)

      expect(result).to be_success
      expect(result.invoice).to have_attributes(
        invoice_type: "credit_purchase",
        status: "open",
        customer:,
        currency: wallet.currency,
        billing_entity: customer.billing_entity,
        purchase_order_number: "PO-1",
        issuing_date: Date.new(2026, 3, 15),
        fees_amount_cents: 8_000,
        taxes_amount_cents: 0,
        total_amount_cents: 8_000
      )
      expect(result.fee).to have_attributes(
        invoice: result.invoice,
        fee_type: "credit_purchase",
        amount_cents: 8_000,
        invoiceable: wallet_transaction,
        contract_id: nil,
        contract_rate_card_id: nil
      )
    end
  end

  it "links the entry and leaves it pending with its wallet untouched" do
    expect(result).to be_success
    expect(wallet_transaction.reload).to have_attributes(
      invoice: result.invoice,
      status: "pending",
      remaining_credit_amount_cents: 10_000
    )
    expect(wallet.reload.balance_cents).to eq(5_000)
  end

  it "requests no payment" do
    expect { result }
      .to not_have_enqueued_job(SendWebhookJob)
      .and not_have_enqueued_job(Invoices::Payments::CreateJob)
      .and not_have_enqueued_job(Invoices::ProviderTaxes::PullTaxesAndApplyJob)
      .and not_change(Payment, :count)
  end

  context "when the wallet has a tax" do
    before { create(:catalog_wallet_applied_tax, catalog_wallet: wallet, tax:, organization:) }

    it "taxes the fee then totals the invoice" do
      expect(result).to be_success
      expect(result.fee).to have_attributes(taxes_amount_cents: 1_600, taxes_rate: 20) # 8_000 * 20 / 100
      expect(result.fee.applied_taxes.map(&:tax_id)).to eq([tax.id])
      expect(result.invoice.reload).to have_attributes(
        status: "open",
        fees_amount_cents: 8_000,
        sub_total_excluding_taxes_amount_cents: 8_000,
        taxes_amount_cents: 1_600, # 8_000 * 20 / 100
        sub_total_including_taxes_amount_cents: 9_600, # 8_000 + 1_600
        total_amount_cents: 9_600 # 8_000 + 1_600
      )
      expect(result.invoice.applied_taxes.map(&:tax_id)).to eq([tax.id])
    end

    context "when the customer is linked to a tax provider" do
      let(:customer) { create(:customer, :with_tax_integration, organization:, timezone: "America/New_York") }

      it_behaves_like "an untaxed hidden purchase"
    end

    context "when the customer's VIES check is running" do
      let(:billing_entity) { create(:billing_entity, organization:, eu_tax_management: true) }
      let(:customer) { create(:customer, organization:, billing_entity:, timezone: "America/New_York") }

      before { create(:pending_vies_check, customer:) }

      it_behaves_like "an untaxed hidden purchase"
    end
  end

  context "when the wallet has no tax" do
    context "when the customer has a tax" do
      before { create(:customer_applied_tax, customer:, tax:, organization:) }

      it "taxes the fee with the customer's tax then totals the invoice" do
        expect(result).to be_success
        expect(result.fee.taxes_amount_cents).to eq(1_600) # 8_000 * 20 / 100
        expect(result.invoice.total_amount_cents).to eq(9_600) # 8_000 + 1_600
        expect(result.invoice.applied_taxes.map(&:tax_id)).to eq([tax.id])
      end
    end
  end

  context "when the wallet is taxed on consumption" do
    let(:tax_application) { "tax_on_consumption" }

    before do
      create(:customer_applied_tax, customer:, tax:, organization:)
      create(:billing_entity_applied_tax, billing_entity: customer.billing_entity, tax:, organization:)
    end

    it_behaves_like "an untaxed hidden purchase"
  end

  context "when the contract has its own billing entity" do
    let(:contract) { create(:contract, organization:, customer:, billing_entity: contract_billing_entity) }
    let(:contract_billing_entity) { create(:billing_entity, organization:) }
    let(:contract_entity_tax) { create(:tax, organization:, rate: 10) }

    before do
      create(:billing_entity_applied_tax, billing_entity: customer.billing_entity, tax:, organization:)
      create(:billing_entity_applied_tax, billing_entity: contract_billing_entity, tax: contract_entity_tax, organization:)
    end

    it "issues the invoice from the customer's billing entity with its default taxes" do
      expect(result).to be_success
      expect(result.invoice.billing_entity).to eq(customer.billing_entity)
      expect(result.fee.billing_entity_id).to eq(customer.billing_entity_id)
      expect(result.fee.taxes_amount_cents).to eq(1_600) # 8_000 * 20 / 100, not the contract entity's 10%
      expect(result.invoice.taxes_amount_cents).to eq(1_600)
    end
  end

  context "when the contract has no purchase order number" do
    let(:contract) { create(:contract, organization:, customer:, purchase_order_number: nil) }

    it "leaves the invoice without one" do
      expect(result).to be_success
      expect(result.invoice.purchase_order_number).to be_nil
    end
  end

  context "when the contract selects an invoice custom section" do
    let(:section) { create(:invoice_custom_section, organization:) }

    before { create(:contract_applied_invoice_custom_section, organization:, contract:, invoice_custom_section: section) }

    it "copies the selection onto the invoice" do
      expect(result.invoice.applied_invoice_custom_sections.pluck(:code)).to eq([section.code])
    end
  end

  context "when the contract skips invoice custom sections" do
    let(:contract) { create(:contract, organization:, customer:, skip_invoice_custom_sections: true) }

    before { create(:customer_applied_invoice_custom_section, organization:, customer:) }

    it "applies no section, not the customer's" do
      expect(result).to be_success
      expect(result.invoice.applied_invoice_custom_sections).to be_empty
    end
  end

  context "when the entry already has its invoice" do
    let(:first_result) { described_class.call(wallet_transaction: CatalogWalletTransaction.find(wallet_transaction.id)) }

    before { first_result }

    it "returns the same invoice and fee" do
      expect { result }.to not_change(Invoice, :count).and not_change(Fee, :count)

      expect(result).to be_success
      expect(result.invoice).to eq(first_result.invoice)
      expect(result.fee).to eq(first_result.fee)
    end
  end

  context "when a settled entry already has its invoice" do
    let(:built_invoice) { create(:invoice, :credit_purchase, :open, organization:, customer:) }
    let(:built_fee) { create(:credit_purchase_fee, invoice: built_invoice, wallet_transaction:, amount_cents: 8_000) }
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, organization:, catalog_wallet: wallet, purchase_amount_cents: 8_000, invoice: built_invoice)
    end

    before { built_fee }

    it "returns its invoice and fee" do
      expect { result }.to not_change(Invoice, :count).and not_change(Fee, :count)

      expect(result).to be_success
      expect(result.invoice).to eq(built_invoice)
      expect(result.fee).to eq(built_fee)
    end
  end

  context "when a record written with the invoice is invalid" do
    before do
      wallet_transaction
      allow(wallet_transaction).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(wallet_transaction))
    end

    it "fails with nothing written" do
      expect { result }.to not_change(Invoice, :count).and not_change(Fee, :count)

      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(wallet_transaction.reload.invoice_id).to be_nil
    end

    context "when the caller already holds a transaction" do
      subject(:result) { ActiveRecord::Base.transaction { described_class.call(wallet_transaction:) } }

      it "fails with nothing written" do
        expect { result }.to not_change(Invoice, :count).and not_change(Fee, :count)

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end

  context "when the customer is a partner account without revenue share" do
    let(:customer) { create(:customer, organization:, account_type: "partner", timezone: "America/New_York") }

    it_behaves_like "a refused entry", "feature_unavailable"
  end

  context "when the entry is outbound" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :invoice_application, organization:, catalog_wallet: wallet)
    end

    it_behaves_like "a refused entry", "wallet_transaction_not_inbound"
  end

  context "when the entry is free" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :pending, organization:, catalog_wallet: wallet, purchase_amount_cents: 0)
    end

    it_behaves_like "a refused entry", "wallet_transaction_not_paid"
  end

  context "when the paid entry is settled" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, organization:, catalog_wallet: wallet, purchase_amount_cents: 8_000)
    end

    it_behaves_like "a refused entry", "wallet_transaction_not_pending"
  end

  context "when the paid entry failed" do
    let(:wallet_transaction) do
      create(:catalog_wallet_transaction, :failed, organization:, catalog_wallet: wallet, purchase_amount_cents: 8_000)
    end

    it_behaves_like "a refused entry", "wallet_transaction_not_pending"
  end

  context "with a premium license", :premium do
    context "when the customer has an invoice grace period" do
      let(:customer) { create(:customer, organization:, timezone: "America/New_York", invoice_grace_period: 3) }

      it "keeps the invoice hidden" do
        expect(result.invoice.status).to eq("open")
      end
    end
  end
end
