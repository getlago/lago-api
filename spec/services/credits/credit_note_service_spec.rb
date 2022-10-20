# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Credits::CreditNoteService do
  subject(:credit_service) do
    described_class.new(
      invoice: invoice,
      credit_notes: [credit_note1, credit_note2],
    )
  end

  let(:invoice) do
    create(
      :invoice,
      customer: customer,
      amount_cents: amount_cents,
      amount_currency: 'EUR',
      total_amount_cents: amount_cents,
      total_amount_currency: 'EUR',
    )
  end

  let(:amount_cents) { 100 }
  let(:customer) { create(:customer) }

  let(:credit_note1) do
    create(
      :credit_note,
      total_amount_cents: 20,
      balance_amount_cents: 20,
      credit_amount_cents: 20,
      customer: customer,
    )
  end

  let(:credit_note2) do
    create(
      :credit_note,
      total_amount_cents: 50,
      balance_amount_cents: 50,
      credit_amount_cents: 50,
      customer: customer,
    )
  end

  describe '.call' do
    it 'creates a list of credits' do
      result = credit_service.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.credits.count).to eq(2)

        credit1 = result.credits.first
        expect(credit1.invoice).to eq(invoice)
        expect(credit1.credit_note).to eq(credit_note1)
        expect(credit1.amount_cents).to eq(20)
        expect(credit1.amount_currency).to eq('EUR')
        expect(credit_note1.reload.balance_amount_cents).to be_zero
        expect(credit_note1).to be_consumed

        credit2 = result.credits.last
        expect(credit2.invoice).to eq(invoice)
        expect(credit2.credit_note).to eq(credit_note2)
        expect(credit2.amount_cents).to eq(50)
        expect(credit2.amount_currency).to eq('EUR')
        expect(credit_note2.reload.balance_amount_cents).to be_zero
        expect(credit_note1).to be_consumed
      end
    end

    context 'when invoice amount is 0' do
      let(:amount_cents) { 0 }

      it 'does not create a credit' do
        result = credit_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.credits.count).to eq(0)
        end
      end
    end

    context 'when credit amount is higher than invoice amount' do
      let(:amount_cents) { 10 }

      it 'creates a credit with partial credit note amount' do
        result = credit_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.credits.count).to eq(1)

          credit = result.credits.first
          expect(credit.invoice).to eq(invoice)
          expect(credit.credit_note).to eq(credit_note1)
          expect(credit.amount_cents).to eq(10)
          expect(credit.amount_currency).to eq('EUR')
          expect(credit_note1.reload.balance_amount_cents).to eq(10)
          expect(credit_note1).to be_available
        end
      end
    end
  end
end
