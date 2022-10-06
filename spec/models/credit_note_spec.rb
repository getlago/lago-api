# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNote, type: :model do
  describe 'sequential_id' do
    let(:invoice) { create(:invoice) }
    let(:customer) { invoice.customer }

    let(:credit_note) do
      build(:credit_note, invoice: invoice, customer: customer)
    end

    it 'assigns a sequential_id is present' do
      credit_note.save

      aggregate_failures do
        expect(credit_note).to be_valid
        expect(credit_note.sequential_id).to eq(1)
      end
    end

    context 'when sequential_id is present' do
      before { credit_note.sequential_id = 3 }

      it 'does not replace the sequential_id' do
        credit_note.save

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(3)
        end
      end
    end

    context 'when credit note already exists' do
      before do
        create(
          :credit_note,
          invoice: invoice,
          sequential_id: 5,
        )
      end

      it 'takes the next available id' do
        credit_note.save!

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(6)
        end
      end
    end

    context 'with credit note on other invoice' do
      before do
        create(
          :credit_note,
          sequential_id: 1,
        )
      end

      it 'scopes the sequence to the invoice' do
        credit_note.save

        aggregate_failures do
          expect(credit_note).to be_valid
          expect(credit_note.sequential_id).to eq(1)
        end
      end
    end
  end

  describe 'number' do
    let(:invoice) { create(:invoice, number: 'CUST-001') }
    let(:customer) { invoice.customer }
    let(:credit_note) { build(:credit_note, invoice: invoice, customer: customer) }

    it 'generates the credit_note_number' do
      credit_note.save

      expect(credit_note.number).to eq('CUST-001-CN001')
    end
  end
end
