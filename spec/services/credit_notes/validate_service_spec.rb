# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::ValidateService, type: :service do
  subject(:validator) { described_class.new(result, item: credit_note) }

  let(:result) { BaseService::Result.new }
  let(:amount_cents) { 10 }
  let(:credit_amount_cents) { 10 }
  let(:refund_amount_cents) { 0 }
  let(:credit_note) do
    create(
      :credit_note,
      invoice: invoice,
      customer: customer,
      credit_amount_cents: credit_amount_cents,
      refund_amount_cents: refund_amount_cents,
    )
  end
  let(:item) do
    create(
      :credit_note_item,
      credit_note: credit_note,
      amount_cents: amount_cents,
      fee: fee,
    )
  end

  let(:invoice) { create(:invoice, total_amount_cents: 100, amount_cents: 100) }
  let(:customer) { invoice.customer }

  let(:fee) do
    create(
      :fee,
      invoice: invoice,
      amount_cents: 100,
    )
  end

  before { item }

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
        create(:fee, invoice: invoice, amount_cents: 100, vat_amount_cents: 20)
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
        create(:fee, invoice: invoice, amount_cents: 100, vat_amount_cents: 20)
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

    context 'when reaching invoice refundable amount' do
      before do
        invoice.succeeded!
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
