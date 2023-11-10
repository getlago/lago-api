# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::ValidateService, type: :service do
  subject(:validator) { described_class.new(result, item: credit_note) }

  let(:result) { BaseService::Result.new }
  let(:amount_cents) { 10 }
  let(:credit_amount_cents) { 12 }
  let(:refund_amount_cents) { 0 }
  let(:credit_note) do
    create(
      :credit_note,
      invoice:,
      customer:,
      credit_amount_cents:,
      refund_amount_cents:,
      precise_coupons_adjustment_amount_cents: 0,
      precise_taxes_amount_cents: 2,
    )
  end
  let(:item) do
    create(
      :credit_note_item,
      credit_note:,
      amount_cents:,
      precise_amount_cents: amount_cents,
      fee:,
    )
  end

  let(:invoice) { create(:invoice, total_amount_cents: 120) }
  let(:customer) { invoice.customer }

  let(:fee) do
    create(
      :fee,
      invoice:,
      amount_cents: 100,
      taxes_rate: 20,
    )
  end

  before do
    item
    credit_note.reload
  end

  describe '.call' do
    it 'validates the credit_note' do
      expect(validator).to be_valid
    end

    context 'when invoice is not paid' do
      let(:invoice_status) { 'pending' }
      let(:refund_amount_cents) { 2 }

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:refund_amount_cents]).to eq(['cannot_refund_unpaid_invoice'])
        end
      end
    end

    context 'when amount does not matches items' do
      let(:amount_cents) { 1 }

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:base]).to eq(['does_not_match_item_amounts'])
        end
      end
    end

    context 'when credit amount is higher than invoice amount' do
      let(:credit_amount_cents) { 250 }

      before do
        create(:fee, invoice:, amount_cents: 100, taxes_rate: 20, taxes_amount_cents: 20)
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:credit_amount_cents]).to eq(['higher_than_remaining_invoice_amount'])
        end
      end
    end

    context 'when refund amount is higher than invoice amount' do
      let(:refund_amount_cents) { 200 }

      before do
        invoice.succeeded!
        create(:fee, invoice:, amount_cents: 100, taxes_rate: 20, taxes_amount_cents: 20)
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:refund_amount_cents]).to eq(['higher_than_remaining_invoice_amount'])
        end
      end
    end

    context 'when reaching invoice creditable amount' do
      before do
        create(:credit_note, invoice:, total_amount_cents: 99)
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:credit_amount_cents]).to eq(['higher_than_remaining_invoice_amount'])
        end
      end
    end

    context 'when reaching invoice refundable amount' do
      before do
        invoice.succeeded!
        create(:credit_note, invoice:, total_amount_cents: 119, refund_amount_cents: 199, credit_amount_cents: 0)
      end

      let(:credit_amount_cents) { 0 }
      let(:refund_amount_cents) { 10 }

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:refund_amount_cents]).to eq(['higher_than_remaining_invoice_amount'])
        end
      end
    end

    context 'when total amount is higher than invoice amount' do
      before do
        create(
          :credit_note,
          invoice:,
          credit_amount_cents: 86,
          refund_amount_cents: 33,
          total_amount_cents: 119,
        )
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:base]).to eq(['higher_than_remaining_invoice_amount'])
        end
      end
    end

    context 'when invoice is v3 with coupons' do
      let(:invoice) do
        create(
          :invoice,
          currency: 'EUR',
          fees_amount_cents: 100,
          coupons_amount_cents: 10,
          taxes_amount_cents: 18,
          total_amount_cents: 108,
          payment_status: :succeeded,
          taxes_rate: 20,
          version_number: 3,
        )
      end

      let(:amount_cents) { 20 }
      let(:credit_amount_cents) { 22 }
      let(:refund_amount_cents) { 0 }
      let(:credit_note) do
        create(
          :credit_note,
          invoice:,
          customer:,
          credit_amount_cents:,
          refund_amount_cents:,
          precise_coupons_adjustment_amount_cents: 2,
          precise_taxes_amount_cents: 3.6,
        )
      end
      let(:item) do
        create(
          :credit_note_item,
          credit_note:,
          amount_cents:,
          precise_amount_cents: amount_cents,
          fee:,
        )
      end

      it 'validates the credit_note' do
        expect(validator).to be_valid
      end

      context 'when amount does not matches items' do
        let(:amount_cents) { 1 }

        it 'fails the validation' do
          aggregate_failures do
            expect(validator).not_to be_valid

            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:base]).to eq(['does_not_match_item_amounts'])
          end
        end
      end
    end
  end
end
