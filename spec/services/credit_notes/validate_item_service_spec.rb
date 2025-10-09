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
  end
end
