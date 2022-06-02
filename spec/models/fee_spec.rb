# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fee, type: :model do
  subject(:fee_model) { described_class }

  describe '.subscription_fee?' do
    it 'checks non presence of charge and add-on' do
      expect(fee_model.new.subscription_fee?).to be_truthy
    end
  end

  describe '.charge_fee?' do
    it 'checks presence of charge' do
      expect(fee_model.new(charge_id: SecureRandom.uuid).charge_fee?).to be_truthy
    end
  end

  describe '.add_on_fee?' do
    it 'checks presence of the add-on' do
      expect(fee_model.new(applied_add_on_id: SecureRandom.uuid).add_on_fee?).to be_truthy
    end
  end

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

  describe '.item_type' do
    context 'when it is a subscription fee' do
      it 'returns subscription' do
        expect(fee_model.new.item_type).to eq('subscription')
      end
    end

    context 'when it is a charge fee' do
      it 'returns charge' do
        expect(fee_model.new(charge_id: SecureRandom.uuid).item_type).to eq('charge')
      end
    end

    context 'when it is a add-on fee' do
      it 'returns add_on' do
        expect(fee_model.new(applied_add_on_id: SecureRandom.uuid).item_type).to eq('add_on')
      end
    end
  end

  describe '.item_code' do
    context 'when it is a subscription fee' do
      let(:subscription) { create(:subscription) }

      it 'returns related subscription code' do
        expect(fee_model.new(subscription: subscription).item_code).to eq(subscription.plan.code)
      end
    end

    context 'when it is a charge fee' do
      let(:charge) { create(:standard_charge) }

      it 'returns related billable metric code' do
        expect(fee_model.new(charge: charge).item_code).to eq(charge.billable_metric.code)
      end
    end

    context 'when it is a add-on fee' do
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns add on code' do
        expect(fee_model.new(applied_add_on: applied_add_on).item_code).to eq(applied_add_on.add_on.code)
      end
    end
  end

  describe '.item_name' do
    context 'when it is a subscription fee' do
      let(:subscription) { create(:subscription) }

      it 'returns related subscription name' do
        expect(fee_model.new(subscription: subscription).item_name).to eq(subscription.plan.name)
      end
    end

    context 'when it is a charge fee' do
      let(:charge) { create(:standard_charge) }

      it 'returns related billable metric name' do
        expect(fee_model.new(charge: charge).item_name).to eq(charge.billable_metric.name)
      end
    end

    context 'when it is a add-on fee' do
      let(:applied_add_on) { create(:applied_add_on) }

      it 'returns add on name' do
        expect(fee_model.new(applied_add_on: applied_add_on).item_name).to eq(applied_add_on.add_on.name)
      end
    end
  end
end
