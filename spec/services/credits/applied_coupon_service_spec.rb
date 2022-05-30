# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Credits::AppliedCouponService do
  subject(:credit_service) { described_class.new(invoice: invoice, applied_coupon: applied_coupon) }

  let(:invoice) do
    create(
      :invoice,
      amount_cents: amount_cents,
      amount_currency: 'EUR',
    )
  end
  let(:amount_cents) { 123 }

  let(:applied_coupon) { create(:applied_coupon, amount_cents: 12) }

  describe 'create' do
    it 'creates a credit' do
      result = credit_service.create

      expect(result).to be_success

      expect(result.credit.amount_cents).to eq(12)
      expect(result.credit.amount_currency).to eq('EUR')
      expect(result.credit.invoice).to eq(invoice)
      expect(result.credit.applied_coupon).to eq(applied_coupon)
    end

    it 'terminates the applied coupon' do
      result = credit_service.create

      expect(result).to be_success
      expect(applied_coupon.reload).to be_terminated
    end

    context 'when coupon amount is higher than invoice amount' do
      let(:amount_cents) { 10 }

      it 'limits the credit amount to the invoice amount' do
        result = credit_service.create

        expect(result).to be_success
        expect(result.credit.amount_cents).to eq(10)
      end

      it 'does not terminate the applied coupon' do
        result = credit_service.create

        expect(result).to be_success
        expect(applied_coupon.reload).not_to be_terminated
      end
    end

    context 'when credit has already been applied' do
      before do
        create(
          :credit,
          invoice: invoice,
          applied_coupon: applied_coupon,
          amount_cents: 12,
          amount_currency: 'EUR',
        )
      end

      it 'does not create another credit' do
        expect { credit_service.create }
          .not_to change(Credit, :count)
      end
    end

    context 'when coupon is partialy used' do
      before do
        create(
          :credit,
          applied_coupon: applied_coupon,
          amount_cents: 10,
        )
      end

      it 'applies the remaining amount' do
        result = credit_service.create

        expect(result).to be_success

        expect(result.credit.amount_cents).to eq(2)
        expect(result.credit.amount_currency).to eq('EUR')
        expect(result.credit.invoice).to eq(invoice)
        expect(result.credit.applied_coupon).to eq(applied_coupon)
      end

      it 'terminates the applied coupon' do
        result = credit_service.create

        expect(result).to be_success
        expect(applied_coupon.reload).to be_terminated
      end
    end
  end
end
