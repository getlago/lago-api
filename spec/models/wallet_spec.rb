# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallet do
  subject(:wallet) { build(:wallet) }

  it_behaves_like "paper_trail traceable"

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:rate_amount).is_greater_than(0) }
    it { is_expected.to validate_inclusion_of(:currency).in_array(described_class.currency_list) }
    it { is_expected.to validate_exclusion_of(:invoice_requires_successful_payment).in_array([nil]) }
    it { is_expected.to validate_numericality_of(:paid_top_up_min_amount_cents).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:paid_top_up_max_amount_cents).is_greater_than(0).allow_nil }
    it { is_expected.to validate_inclusion_of(:priority).in_range(1..50) }

    it "validates than max is greater than min" do
      subject.paid_top_up_min_amount_cents = 100
      subject.paid_top_up_max_amount_cents = 1

      expect(subject).not_to be_valid
      expect(subject.errors["paid_top_up_max_amount_cents"]).to eq ["must_be_greater_than_or_equal_min"]

      subject.paid_top_up_max_amount_cents = subject.paid_top_up_min_amount_cents
      expect(subject).to be_valid
      expect(subject.errors).to be_empty
    end
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

  describe "limited_to_billable_metrics?" do
    context "when wallet_targets are present" do
      before { create(:wallet_target, wallet:) }

      it "returns true" do
        expect(wallet.limited_to_billable_metrics?).to be true
      end
    end

    context "when wallet targets are not present" do
      it "returns false" do
        expect(wallet.limited_to_billable_metrics?).to be false
      end
    end
  end

  describe "#paid_top_up_min_credits" do
    it "converts min amount cents to credits using the wallet rate" do
      wallet.rate_amount = 25
      wallet.paid_top_up_min_amount_cents = 1_00
      expect(wallet.paid_top_up_min_credits).to eq(0.04)

      wallet.paid_top_up_min_amount_cents = nil
      expect(wallet.paid_top_up_min_credits).to be_nil
    end
  end

  describe "#paid_top_up_max_credits" do
    it "converts max amount cents to credits using the wallet rate" do
      wallet.paid_top_up_max_amount_cents = 5_00
      expect(wallet.paid_top_up_max_credits).to eq(5.0)

      wallet.paid_top_up_max_amount_cents = nil
      expect(wallet.paid_top_up_max_credits).to be_nil
    end
  end
end
