# frozen_string_literal: true

require "rails_helper"

describe Fees::CreateCreditPurchaseService do
  subject(:result) { described_class.call(invoice:, wallet_transaction:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:wallet) { create(:catalog_wallet, organization:, customer:, contract:) }
  let(:purchase_amount_cents) { 8_000 }
  let(:credit_amount_cents) { 10_000 }
  let(:wallet_transaction) do
    create(
      :catalog_wallet_transaction,
      :pending,
      organization:,
      catalog_wallet: wallet,
      purchase_amount_cents:,
      credit_amount_cents:
    )
  end
  let(:invoice) { create(:invoice, :credit_purchase, organization:, customer:, currency: wallet.currency) }

  it "creates the purchase fee of the entry" do
    expect { result }.to change(Fee, :count).by(1)

    expect(result).to be_success
    expect(result.fee).to be_persisted
    expect(result.fee).to have_attributes(
      fee_type: "credit_purchase",
      invoice:,
      organization_id: organization.id,
      billing_entity_id: invoice.billing_entity_id,
      invoiceable: wallet_transaction,
      invoiceable_type: "CatalogWalletTransaction",
      amount_cents: 8_000, # the entry's price
      precise_amount_cents: 8_000,
      amount_currency: wallet.currency,
      units: 100, # 10_000 credit cents / 100 subunits per unit
      precise_unit_amount: BigDecimal("0.8"), # 8_000 price cents / 10_000 credit cents
      unit_amount_cents: 80, # 0.8 * 100 subunits per unit
      payment_status: "pending",
      contract_id: nil,
      contract_rate_card_id: nil,
      subscription_id: nil,
      taxes_amount_cents: 0,
      taxes_precise_amount_cents: 0,
      taxes_rate: 0
    )
  end

  it "leaves the entry untouched" do
    expect { result }.not_to change { wallet_transaction.reload.attributes }
  end

  context "when the unit amount does not divide evenly" do
    let(:purchase_amount_cents) { 1_000 }
    let(:credit_amount_cents) { 300 }

    it "keeps the precise unit amount and rounds its cents once" do
      expect(result).to be_success
      expect(result.fee.reload).to have_attributes(
        amount_cents: 1_000,
        precise_amount_cents: 1_000,
        units: 3, # 300 credit cents / 100 subunits per unit
        # 1_000 price cents / 300 credit cents = 3.333..., kept to the 15 decimals of the column
        precise_unit_amount: (BigDecimal(1_000) / 300).round(15),
        unit_amount_cents: 333 # (3.333... * 100 subunits per unit).round
      )
    end
  end

  context "when the unit amount rounds up" do
    let(:purchase_amount_cents) { 2_000 }
    let(:credit_amount_cents) { 300 }

    it "rounds the unit amount cents to the nearest cent" do
      expect(result).to be_success
      expect(result.fee.reload).to have_attributes(
        units: 3, # 300 credit cents / 100 subunits per unit
        # 2_000 price cents / 300 credit cents = 6.666..., kept to the 15 decimals of the column
        precise_unit_amount: (BigDecimal(2_000) / 300).round(15),
        unit_amount_cents: 667 # (6.666... * 100 subunits per unit).round
      )
    end
  end

  context "when the wallet currency has no subunit" do
    let(:customer) { create(:customer, organization:, currency: "JPY") }

    it "counts the credit amount as whole units" do
      expect(result).to be_success
      expect(result.fee).to have_attributes(
        amount_cents: 8_000,
        amount_currency: "JPY",
        units: 10_000, # 10_000 credit cents / 1 subunit per unit
        precise_unit_amount: BigDecimal("0.8"), # 8_000 price cents / 10_000 credit cents
        unit_amount_cents: 1 # (0.8 * 1 subunit per unit).round
      )
    end
  end

  context "when the fee is invalid" do
    let(:invalid_fee) { build(:credit_purchase_fee, organization:, invoice:, wallet_transaction:, units: -1) }

    before do
      invalid_fee.validate
      allow(Fee).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid_fee))
    end

    it "fails with the fee validation errors" do
      expect { result }.not_to change(Fee, :count)

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq({units: ["value_is_out_of_range"]})
      expect(result.fee).to be_nil
    end
  end
end
