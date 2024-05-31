# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Credit, type: :model do
  describe 'invoice item' do
    context 'when credit is a coupon' do
      subject(:credit) { create(:credit, applied_coupon:) }

      let(:applied_coupon) { create(:applied_coupon, coupon:) }
      let(:coupon) do
        create(
          :coupon,
          code: 'coupon_code',
          name: 'Coupon name'
        )
      end

      it 'returns coupon details' do
        aggregate_failures do
          expect(credit.item_id).to eq(coupon.id)
          expect(credit.item_type).to eq('coupon')
          expect(credit.item_code).to eq('coupon_code')
          expect(credit.item_name).to eq('Coupon name')
        end
      end

      context 'when coupon is deleted' do
        let(:coupon) do
          create(
            :coupon,
            :deleted,
            code: 'coupon_code',
            name: 'Coupon name',
            amount_cents: 200,
            amount_currency: 'EUR'
          )
        end

        it 'returns coupon details' do
          aggregate_failures do
            expect(credit.item_id).to eq(coupon.id)
            expect(credit.item_type).to eq('coupon')
            expect(credit.item_code).to eq('coupon_code')
            expect(credit.item_name).to eq('Coupon name')
            expect(credit.invoice_coupon_display_name).to eq('Coupon name (€2.00)')
          end
        end
      end
    end

    context 'when credit is a credit note' do
      subject(:credit) { create(:credit_note_credit) }

      let(:credit_note) { credit.credit_note }

      it 'returns credit note details' do
        aggregate_failures do
          expect(credit.item_id).to eq(credit_note.id)
          expect(credit.item_type).to eq('credit_note')
          expect(credit.item_code).to eq(credit_note.number)
          expect(credit.item_name).to eq(credit_note.invoice.number)
        end
      end
    end
  end
end
