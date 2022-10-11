# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::ValidateItemService, type: :service do
  subject(:validator) { described_class.new(result, item: item) }

  let(:result) { BaseService::Result.new }
  let(:credit_amount_cents) { 10 }
  let(:credit_note) do
    create(
      :credit_note,
      invoice: invoice,
      customer: customer,
      amount_cents: 0,
    )
  end
  let(:item) do
    build(
      :credit_note_item,
      credit_note: credit_note,
      credit_amount_cents: credit_amount_cents,
      fee: fee,
    )
  end
  let(:invoice) { create(:invoice, total_amount_cents: 100) }
  let(:customer) { invoice.customer }

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

    context 'when fee already has credit note items' do
      before { create(:credit_note_item, fee: fee, credit_amount_cents: 99) }

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:credit_amount_cents]).to eq(['higher_than_remaining_fee_amount'])
        end
      end
    end

    context 'when invoice already has credit note items' do
      before do
        create(:credit_note, invoice: invoice, amount_cents: 99)
      end

      it 'fails the validation' do
        aggregate_failures do
          expect(validator).not_to be_valid

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:credit_amount_cents]).to eq(['higher_than_remaining_invoice_amount'])
        end
      end
    end
  end
end
