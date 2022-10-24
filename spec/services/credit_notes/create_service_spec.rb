# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::CreateService, type: :service do
  subject(:create_service) { described_class.new(invoice: invoice, items_attr: items) }

  let(:invoice) do
    create(:invoice, amount_currency: 'EUR', amount_cents: 20, total_amount_cents: 20, status: :succeeded)
  end
  let(:fee1) { create(:fee, invoice: invoice, amount_cents: 10) }
  let(:fee2) { create(:fee, invoice: invoice, amount_cents: 10) }
  let(:items) do
    [
      {
        fee_id: fee1.id,
        credit_amount_cents: 10,
        refund_amount_cents: 2,
      },
      {
        fee_id: fee2.id,
        credit_amount_cents: 5,
        refund_amount_cents: 2,
      },
    ]
  end

  describe '.call' do
    it 'creates a credit note' do
      result = create_service.call

      aggregate_failures do
        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note.invoice).to eq(invoice)
        expect(credit_note.customer).to eq(invoice.customer)

        expect(credit_note.total_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.total_amount_cents).to eq(19)

        expect(credit_note.credit_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.credit_amount_cents).to eq(15)
        expect(credit_note.balance_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.balance_amount_cents).to eq(15)
        expect(credit_note.credit_status).to eq('available')

        expect(credit_note.refund_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.refund_amount_cents).to eq(4)
        expect(credit_note.refund_status).to eq('pending')

        expect(credit_note).to be_other

        expect(credit_note.items.count).to eq(2)
        item1 = credit_note.items.order(created_at: :asc).first
        expect(item1.fee).to eq(fee1)
        expect(item1.credit_amount_cents).to eq(10)
        expect(item1.credit_amount_currency).to eq(invoice.amount_currency)
        expect(item1.refund_amount_cents).to eq(2)
        expect(item1.refund_amount_currency).to eq(invoice.amount_currency)

        item2 = credit_note.items.order(created_at: :asc).last
        expect(item2.fee).to eq(fee2)
        expect(item2.credit_amount_cents).to eq(5)
        expect(item2.credit_amount_currency).to eq(invoice.amount_currency)
        expect(item2.refund_amount_cents).to eq(2)
        expect(item2.refund_amount_currency).to eq(invoice.amount_currency)
      end
    end

    context 'with invalid items' do
      let(:items) do
        [
          {
            fee_id: fee1.id,
            credit_amount_cents: 10,
          },
          {
            fee_id: fee2.id,
            credit_amount_cents: 15,
          },
        ]
      end

      it 'returns a failed result' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:credit_amount_cents)
          expect(result.error.messages[:credit_amount_cents]).to eq(
            %w[
              higher_than_remaining_fee_amount
              higher_than_remaining_invoice_amount
            ],
          )
        end
      end
    end
  end
end
