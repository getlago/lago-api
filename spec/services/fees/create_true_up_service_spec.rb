# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::CreateTrueUpService, type: :service do
  subject(:create_service) { described_class.new(fee:) }

  let(:charge) { create(:standard_charge, min_amount_cents: 1000) }
  let(:fee) { create(:charge_fee, amount_cents: 700, charge: charge) }

  describe '#call' do
    context 'when fee is nil' do
      let(:fee) { nil }

      it 'does not instantiate a true-up fee' do
        result = create_service.call
        expect(result.true_up_fee).to be_nil
      end
    end

    context 'when min_amount_cents is lower than the fee amount_cents' do
      let(:fee) { create(:charge_fee, amount_cents: 1500) }

      it 'does not instantiate a true-up fee' do
        result = create_service.call
        expect(result.true_up_fee).to be_nil
      end
    end

    it 'instantiates a true-up fee' do
      result = create_service.call

      aggregate_failures do
        expect(result).to be_success

        expect(result.true_up_fee).to have_attributes(
          subscription: fee.subscription,
          charge: fee.charge,
          amount_currency: fee.currency,
          vat_rate: fee.vat_rate,
          fee_type: 'charge',
          invoiceable: fee.charge,
          properties: fee.properties,
          payment_status: 'pending',
          units: 1,
          events_count: 0,
          group: nil,
          amount_cents: 300,
          vat_amount_cents: 0,
          vat_amount_currency: fee.currency,
        )
      end
    end
  end
end
