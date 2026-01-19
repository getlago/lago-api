# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::ValidateItemService do
  subject(:validator) { described_class.new(result, item:) }

  let(:result) { BaseService::Result.new }
  let(:amount_cents) { 10 }
  let(:credit_amount_cents) { 10 }
  let(:refund_amount_cents) { 0 }
  let(:credit_note) do
    create(
      :credit_note,
      invoice:,
      customer:,
      credit_amount_cents:,
      refund_amount_cents:
    )
  end
  let(:item) do
    build(
      :credit_note_item,
      credit_note:,
      amount_cents:,
      fee:
    )
  end

  let(:invoice) { create(:invoice, total_amount_cents: 120) }
  let(:customer) { invoice.customer }

  let(:fee) { create(:fee, invoice:, amount_cents: 100, taxes_rate: 20) }

  describe ".call" do
    it "validates the item" do
      expect(validator).to be_valid
    end

    context "when fee is missing" do
      let(:fee) { nil }

      it "fails the validation" do
        expect(validator).not_to be_valid

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("fee")
      end
    end

    context "when amount is negative" do
      let(:amount_cents) { -3 }

      it "fails the validation" do
        expect(validator).not_to be_valid

        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:amount_cents]).to eq(["invalid_value"])
      end
    end

    context "when amount is zero" do
      let(:amount_cents) { 0 }

      it "passes the validation" do
        expect(validator).to be_valid
      end
    end

    context "when amount is higher than fee amount" do
      let(:amount_cents) { fee.amount_cents + 10 }

      before do
        create(:fee, invoice:, amount_cents: 100, taxes_rate: 20, taxes_amount_cents: 20)
      end

      it "fails the validation" do
        expect(validator).not_to be_valid

        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:amount_cents]).to eq(["higher_than_remaining_fee_amount"])
      end
    end

    context "when reaching fee creditable amount" do
      before do
        create(:credit_note_item, fee:, amount_cents: 99)
        create(:fee, invoice:, amount_cents: 100, taxes_rate: 20, taxes_amount_cents: 20)
      end

      it "fails the validation" do
        expect(validator).not_to be_valid

        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:amount_cents]).to eq(["higher_than_remaining_fee_amount"])
      end
    end

    context "with offset_amount_cents in invoice_credit_note_total_amount_cents calculation" do
      let(:amount_cents) { 20 }

      before do
        create(
          :credit_note,
          invoice:,
          customer:,
          credit_amount_cents: 30,
          refund_amount_cents: 20,
          offset_amount_cents: 15,
          status: :finalized
        )
      end

      it "includes offset amount in total credit note amounts" do
        expect(validator).to be_valid
      end
    end

    context "when offset_amount_cents affects remaining invoice amount" do
      let(:amount_cents) { 50 }

      before do
        # Create credit notes that use up most of the invoice: 30 credit + 20 refund + 40 offset = 90
        create(
          :credit_note,
          invoice:,
          customer:,
          credit_amount_cents: 30,
          refund_amount_cents: 20,
          offset_amount_cents: 40,
          status: :finalized
        )
      end

      it "validates successfully when within remaining amount" do
        expect(validator).to be_valid
      end
    end

    context "when cancelling prepaid credits with offset" do
      let(:invoice) { create(:invoice, :credit, total_amount_cents: 1000, payment_status: :pending) }
      let(:wallet) { create(:wallet, customer:, balance_cents: 1000) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet:) }
      let(:fee) { create(:fee, invoice:, fee_type: :credit, invoiceable: wallet_transaction, amount_cents: 1000) }
      let(:amount_cents) { 1000 }

      before do
        wallet
        # Create a credit note that offsets the full invoice amount
        create(
          :credit_note,
          invoice:,
          customer:,
          credit_amount_cents: 0,
          refund_amount_cents: 0,
          offset_amount_cents: 1000,
          status: :finalized
        )
      end

      it "allows creating additional credit note item when cancelling prepaid credits" do
        expect(validator).to be_valid
      end
    end

    context "with draft credit notes containing offset amounts" do
      let(:amount_cents) { 30 }

      before do
        # Draft credit notes should not be counted
        create(
          :credit_note,
          invoice:,
          customer:,
          credit_amount_cents: 50,
          refund_amount_cents: 30,
          offset_amount_cents: 20,
          status: :draft
        )
      end

      it "does not include draft credit note offset amounts in calculation" do
        expect(validator).to be_valid
      end
    end

    context "when invoice is credit type with offset matching total amount" do
      let(:invoice) { create(:invoice, :credit, total_amount_cents: 500, payment_status: :succeeded) }
      let(:wallet) { create(:wallet, customer:, balance_cents: 500) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet:) }
      let(:fee) { create(:fee, invoice:, fee_type: :credit, invoiceable: wallet_transaction, amount_cents: 500) }
      let(:amount_cents) { 500 }

      before do
        wallet
        # Offset equals invoice total
        create(
          :credit_note,
          invoice:,
          customer:,
          credit_amount_cents: 0,
          refund_amount_cents: 0,
          offset_amount_cents: 500,
          status: :finalized
        )
      end

      it "allows exceeding creditable amount when cancelling prepaid credits" do
        expect(validator).to be_valid
      end
    end

    context "when invoice has only offset amounts in credit notes" do
      let(:amount_cents) { 15 }

      before do
        create(
          :credit_note,
          invoice:,
          customer:,
          credit_amount_cents: 0,
          refund_amount_cents: 0,
          offset_amount_cents: 25,
          status: :finalized
        )
      end

      it "considers offset amounts when validating" do
        expect(validator).to be_valid
      end
    end

    context "when invoice is credit with wallet and higher item amount" do
      let(:invoice) { create(:invoice, :credit, total_amount_cents: 2000, payment_status: :succeeded) }
      let(:wallet) { create(:wallet, customer:, balance_cents: 800) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet:) }
      let(:fee) { create(:fee, invoice:, fee_type: :credit, invoiceable: wallet_transaction, amount_cents: 2000) }
      let(:amount_cents) { 1500 }

      before do
        wallet
      end

      it "fails validation when amount exceeds wallet balance" do
        expect(validator).not_to be_valid

        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:amount_cents]).to eq(["higher_than_wallet_balance"])
      end
    end
  end
end
