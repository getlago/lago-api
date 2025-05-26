# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallet, type: :model do
  subject(:wallet) { build(:wallet) }

  it_behaves_like "paper_trail traceable"

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

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

  describe "limited_fee_types?" do
    context "when allowed_fee_types is present" do
      before { wallet.allowed_fee_types = %w[charge] }

      it "returns true" do
        expect(wallet.limited_fee_types?).to be true
      end
    end

    context "when allowed_fee_types is empty" do
      before { wallet.allowed_fee_types = [] }

      it "returns false" do
        expect(wallet.limited_fee_types?).to be false
      end
    end
  end
end
