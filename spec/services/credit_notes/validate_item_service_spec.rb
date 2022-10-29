# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::ValidateItemService, type: :service do
  subject(:validator) { described_class.new(result, item: item) }

  let(:result) { BaseService::Result.new }
  let(:credit_amount_cents) { 10 }
  let(:refund_amount_cents) { 0 }
  let(:credit_note) do
    create(
      :credit_note,
      invoice: invoice,
      customer: customer,
      credit_amount_cents: 0,
    )
  end
  let(:item) do
    build(
      :credit_note_item,
      credit_note: credit_note,
      credit_amount_cents: credit_amount_cents,
      refund_amount_cents: refund_amount_cents,
      fee: fee,
    )
  end
  let(:invoice) { create(:invoice, total_amount_cents: 100, amount_cents: 100, status: invoice_status) }
  let(:customer) { invoice.customer }
  let(:invoice_status) { 'succeeded' }

  let(:fee) { create(:fee, invoice: invoice, amount_cents: 100) }

  describe '.call' do
    it 'validates the item' do
      expect(validator).to be_valid
    end

    context 'when fee is missing' do
      let(:fee) { nil }

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq('fee')
        end
      end
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

    context 'when credit amount is higher than fee amount' do
      let(:credit_amount_cents) { fee.amount_cents + 10 }

      before do
        create(:fee, invoice: invoice, amount_cents: 100, vat_amount_cents: 20)
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:credit_amount_cents]).to eq(['higher_than_remaining_fee_amount'])
        end
      end
    end

    context 'when reaching fee creditable amount' do
      before { create(:credit_note_item, fee: fee, credit_amount_cents: 99) }

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:credit_amount_cents]).to eq(['higher_than_remaining_fee_amount'])
        end
      end
    end

    context 'when reaching invoice creditable amount' do
      before do
        create(:credit_note, invoice: invoice, total_amount_cents: 99)
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:credit_amount_cents]).to eq(['higher_than_remaining_invoice_amount'])
        end
      end
    end

    context 'when refund amount is higher than fee amount' do
      let(:credit_amount_cents) { 0 }
      let(:refund_amount_cents) { fee.amount_cents + 10 }

      before do
        create(:fee, invoice: invoice, amount_cents: 100, vat_amount_cents: 20)
        invoice.update!(amount_cents: 220, total_amount_cents: 220)
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:refund_amount_cents]).to eq(['higher_than_remaining_fee_amount'])
        end
      end
    end

    context 'when reaching fee refundable amount' do
      before { create(:credit_note_item, fee: fee, credit_amount_cents: 99) }

      let(:credit_amount_cents) { 0 }
      let(:refund_amount_cents) { 10 }

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:refund_amount_cents]).to eq(['higher_than_remaining_fee_amount'])
        end
      end
    end

    context 'when reaching invoice refundable amount' do
      before do
        create(:credit_note, invoice: invoice, total_amount_cents: 99, refund_amount_cents: 99, credit_amount_cents: 0)
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

    context 'when total amount is higher than fee amount' do
      let(:credit_amount_cents) { fee.amount_cents - 5 }
      let(:refund_amount_cents) { 10 }

      before do
        create(:fee, invoice: invoice, amount_cents: 100, vat_amount_cents: 20)
        invoice.update!(amount_cents: 220, total_amount_cents: 220)
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:base]).to eq(['higher_than_remaining_fee_amount'])
        end
      end
    end

    context 'when total amount is higher than invoice amount' do
      before do
        create(
          :credit_note,
          invoice: invoice,
          credit_amount_cents: 66,
          refund_amount_cents: 33,
          total_amount_cents: 99,
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
  end
end
