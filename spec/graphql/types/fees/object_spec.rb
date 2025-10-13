# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Fees::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")

    expect(subject).to have_field(:add_on).of_type("AddOn")
    expect(subject).to have_field(:charge).of_type("Charge")
    expect(subject).to have_field(:currency).of_type("CurrencyEnum!")
    expect(subject).to have_field(:description).of_type("String")
    expect(subject).to have_field(:grouped_by).of_type("JSON!")
    expect(subject).to have_field(:fixed_charge).of_type("FixedCharge")
    expect(subject).to have_field(:invoice_display_name).of_type("String")
    expect(subject).to have_field(:invoice_name).of_type("String")
    expect(subject).to have_field(:subscription).of_type("Subscription")
    expect(subject).to have_field(:true_up_fee).of_type("Fee")
    expect(subject).to have_field(:true_up_parent_fee).of_type("Fee")
    expect(subject).to have_field(:wallet_transaction).of_type("WalletTransaction")

    expect(subject).to have_field(:creditable_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:events_count).of_type("BigInt")
    expect(subject).to have_field(:fee_type).of_type("FeeTypesEnum!")
    expect(subject).to have_field(:precise_unit_amount).of_type("Float!")
    expect(subject).to have_field(:succeeded_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:taxes_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:taxes_rate).of_type("Float")
    expect(subject).to have_field(:units).of_type("Float!")

    expect(subject).to have_field(:applied_taxes).of_type("[FeeAppliedTax!]")

    expect(subject).to have_field(:amount_details).of_type("FeeAmountDetails")

    expect(subject).to have_field(:adjusted_fee).of_type("Boolean!")
    expect(subject).to have_field(:adjusted_fee_type).of_type("AdjustedFeeTypeEnum")

    expect(subject).to have_field(:charge_filter).of_type("ChargeFilter")
    expect(subject).to have_field(:pricing_unit_usage).of_type("PricingUnitUsage")
    expect(subject).to have_field(:properties).of_type("FeeProperties")
  end

  describe "#wallet_transaction" do
    subject { run_graphql_field("Fee.walletTransaction", fee) }

    context "when fee is a credit" do
      let(:fee) { create(:credit_fee) }
      let(:wallet_transaction) { fee.invoiceable }

      it "returns the wallet transaction" do
        expect(subject).to be_present
        expect(subject).to eq(wallet_transaction)
      end
    end

    context "when fee is not a credit" do
      let(:fee) { create(:charge_fee) }

      it "returns nil" do
        expect(subject).to be_nil
      end
    end
  end
end
