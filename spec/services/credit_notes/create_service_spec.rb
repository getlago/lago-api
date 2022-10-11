# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::CreateService, type: :service do
  subject(:create_service) { described_class.new(invoice: invoice, items_attr: items) }

  let(:invoice) { create(:invoice, amount_currency: 'EUR', amount_cents: 20, total_amount_cents: 20) }
  let(:fee1) { create(:fee, invoice: invoice, amount_cents: 10) }
  let(:fee2) { create(:fee, invoice: invoice, amount_cents: 10) }
  let(:items) do
    [
      {
        fee_id: fee1.id,
        credit_amount_cents: 10,
      },
      {
        fee_id: fee2.id,
        credit_amount_cents: 5,
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
        expect(credit_note.amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.amount_cents).to eq(15)
        expect(credit_note.remaining_amount_currency).to eq(invoice.amount_currency)
        expect(credit_note.remaining_amount_cents).to eq(15)
        expect(credit_note).to be_other

        expect(credit_note.items.count).to eq(2)
        items1 = credit_note.items.order(created_at: :asc).first
        expect(items1.fee).to eq(fee1)
        expect(items1.credit_amount_cents).to eq(10)
        expect(items1.credit_amount_currency).to eq(invoice.amount_currency)

        items2 = credit_note.items.order(created_at: :asc).last
        expect(items2.fee).to eq(fee2)
        expect(items2.credit_amount_cents).to eq(5)
        expect(items2.credit_amount_currency).to eq(invoice.amount_currency)
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
          expect(result.error.messages.keys).to eq([:credit_amount_cents])
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
