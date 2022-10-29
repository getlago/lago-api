# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fee, type: :model do
  subject(:fee_model) { described_class }

  describe '.compute_vat' do
    it 'computes the vat' do
      fee = fee_model.new(amount_cents: 100, amount_currency: 'EUR', vat_rate: 20.0)

      fee.compute_vat

      aggregate_failures do
        expect(fee.vat_amount_currency).to eq('EUR')
        expect(fee.vat_amount_cents).to eq(20)
      end
    end
  end

  describe '.item_code' do
    context 'when it is a subscription fee' do
      let(:subscription) { create(:subscription) }

      it 'returns related subscription code' do
        expect(fee_model.new(subscription: subscription, fee_type: 'subscription').item_code)
          .to eq(subscription.plan.code)
      end
    end

    context 'when it is a charge fee' do
      let(:charge) { create(:standard_charge) }

      it 'returns related billable metric code' do
        expect(fee_model.new(charge: charge, fee_type: 'charge').item_code)
          .to eq(charge.billable_metric.code)
      end
    end

    context 'when it is a add-on fee' do
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns add on code' do
        expect(fee_model.new(applied_add_on: applied_add_on, fee_type: 'add_on').item_code)
          .to eq(applied_add_on.add_on.code)
      end
    end

    context 'when it is a credit fee' do
      it 'returns add on code' do
        expect(fee_model.new(fee_type: 'credit').item_code).to eq('credit')
      end
    end
  end

  describe '.item_name' do
    context 'when it is a subscription fee' do
      let(:subscription) { create(:subscription) }

      it 'returns related subscription name' do
        expect(fee_model.new(subscription: subscription, fee_type: 'subscription').item_name)
          .to eq(subscription.plan.name)
      end
    end

    context 'when it is a charge fee' do
      let(:charge) { create(:standard_charge) }

      it 'returns related billable metric name' do
        expect(fee_model.new(charge: charge, fee_type: 'charge').item_name)
          .to eq(charge.billable_metric.name)
      end
    end

    context 'when it is a add-on fee' do
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns add on name' do
        expect(fee_model.new(applied_add_on: applied_add_on, fee_type: 'add_on').item_name)
          .to eq(applied_add_on.add_on.name)
      end
    end

    context 'when it is a credit fee' do
      it 'returns add on name' do
        expect(fee_model.new(fee_type: 'credit').item_name).to eq('credit')
      end
    end
  end

  describe '#total_amount_cents' do
    let(:fee) { create(:fee, amount_cents: 100, vat_amount_cents: 20) }

    it 'returns the sum of amount and vat' do
      expect(fee.total_amount_cents).to eq(120)
    end
  end

  describe '#total_amount_currency' do
    let(:fee) { create(:fee, amount_currency: 'EUR') }

    it { expect(fee.total_amount_currency).to eq('EUR') }
  end
end
