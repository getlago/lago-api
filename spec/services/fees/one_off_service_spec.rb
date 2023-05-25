# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::OneOffService do
  subject(:one_off_service) do
    described_class.new(invoice:, fees:)
  end

  let(:invoice) { create(:invoice, organization:) }
  let(:organization) { create(:organization) }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:fees) do
    [
      {
        add_on_code: add_on_first.code,
        unit_amount_cents: 1200,
        units: 2,
        description: 'desc-123',
      },
      {
        add_on_code: add_on_second.code,
      },
    ]
  end

  describe 'create' do
    before { CurrentContext.source = 'api' }

    it 'creates fees' do
      result = one_off_service.create

      expect(result).to be_success

      first_fee = result.fees[0]
      second_fee = result.fees[1]

      aggregate_failures do
        expect(first_fee.id).not_to be_nil
        expect(first_fee.invoice_id).to eq(invoice.id)
        expect(first_fee.add_on_id).to eq(add_on_first.id)
        expect(first_fee.description).to eq('desc-123')
        expect(first_fee.unit_amount_cents).to eq(1200)
        expect(first_fee.units).to eq(2)
        expect(first_fee.amount_cents).to eq(2400)
        expect(first_fee.amount_currency).to eq('EUR')
        expect(first_fee.vat_amount_cents).to eq(480)
        expect(first_fee.vat_rate).to eq(20.0)
        expect(first_fee.fee_type).to eq('add_on')
        expect(first_fee.payment_status).to eq('pending')

        expect(second_fee.id).not_to be_nil
        expect(second_fee.invoice_id).to eq(invoice.id)
        expect(second_fee.add_on_id).to eq(add_on_second.id)
        expect(second_fee.description).to eq(add_on_second.description)
        expect(second_fee.unit_amount_cents).to eq(400)
        expect(second_fee.units).to eq(1)
        expect(second_fee.amount_cents).to eq(400)
        expect(second_fee.amount_currency).to eq('EUR')
        expect(second_fee.vat_amount_cents).to eq(80)
        expect(second_fee.vat_rate).to eq(20.0)
        expect(second_fee.fee_type).to eq('add_on')
        expect(second_fee.payment_status).to eq('pending')
      end
    end

    context 'when add_on_code is invalid' do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: 'desc-123',
          },
          {
            add_on_code: 'invalid',
          },
        ]
      end

      it 'does not create a invalid fee' do
        one_off_service.create

        expect(Fee.find_by(description: add_on_second.description)).to be_nil
      end
    end
  end
end
