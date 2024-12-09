# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallet, type: :model do
  subject(:wallet) { build(:wallet) }

  describe "validations" do
    it { is_expected.to validate_numericality_of(:rate_amount).is_greater_than(0) }
  end

  describe "currency=" do
    it "assigns the currency to all amounts" do
      wallet.currency = "CAD"

      expect(wallet).to have_attributes(
        balance_currency: "CAD",
        consumed_amount_currency: "CAD"
      )
    end
  end

  describe "currency" do
    it "returns the wallet currency" do
      expect(wallet.currency).to eq(wallet.balance_currency)
    end
  end

  describe "#ongoing_draft_invoices_balance_cents" do
    it "returns the sum of ongoing draft invoices" do
      create(:invoice, :draft, customer: wallet.customer, total_amount_cents: 100)
      create(:invoice, :draft, customer: wallet.customer, total_amount_cents: 200)
      create(:invoice, customer: wallet.customer, total_amount_cents: 400)

      expect(wallet.ongoing_draft_invoices_balance_cents).to eq(300)
    end
  end

  describe "#credits_ongoing_draft_invoices_balance" do
    subject(:wallet) { build(:wallet, rate_amount: 1) }

    it "returns the number of credits for ongoing draft invoices" do
      create(:invoice, :draft, customer: wallet.customer, total_amount_cents: 100)
      create(:invoice, :draft, customer: wallet.customer, total_amount_cents: 200)
      create(:invoice, customer: wallet.customer, total_amount_cents: 400)

      expect(wallet.credits_ongoing_draft_invoices_balance).to eq(3)
    end
  end
end
