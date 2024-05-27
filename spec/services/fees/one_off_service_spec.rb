# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::OneOffService do
  subject(:one_off_service) do
    described_class.new(invoice:, fees:)
  end

  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:) }
  let(:tax2) { create(:tax, organization:, applied_to_organization: false) }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:fees) do
    [
      {
        add_on_code: add_on_first.code,
        unit_amount_cents: 1200,
        units: 2,
        description: 'desc-123',
        tax_codes: [tax2.code]
      },
      {
        add_on_code: add_on_second.code
      }
    ]
  end

  before { tax }

  describe 'create' do
    before { CurrentContext.source = 'api' }

    it 'creates fees' do
      result = one_off_service.create

      expect(result).to be_success

      first_fee = result.fees[0]
      second_fee = result.fees[1]

      aggregate_failures do
        expect(first_fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          add_on_id: add_on_first.id,
          description: 'desc-123',
          unit_amount_cents: 1200,
          precise_unit_amount: 12,
          units: 2,
          amount_cents: 2400,
          amount_currency: 'EUR',
          fee_type: 'add_on',
          payment_status: 'pending',
        )
        expect(first_fee.taxes.map(&:code)).to contain_exactly(tax2.code)

        expect(second_fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          add_on_id: add_on_second.id,
          description: add_on_second.description,
          unit_amount_cents: 400,
          precise_unit_amount: 4,
          units: 1,
          amount_cents: 400,
          amount_currency: 'EUR',
          fee_type: 'add_on',
          payment_status: 'pending',
        )
        expect(second_fee.taxes.map(&:code)).to contain_exactly(tax.code)
      end
    end

    context 'when add_on_code is invalid' do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: 'desc-123'
          },
          {
            add_on_code: 'invalid'
          }
        ]
      end

      it 'does not create an invalid fee' do
        one_off_service.create

        expect(Fee.find_by(description: add_on_second.description)).to be_nil
      end
    end

    context 'when units is passed as string' do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: 'desc-123',
            tax_codes: [tax2.code]
          }
        ]
      end

      it 'creates fees' do
        result = one_off_service.create

        expect(result).to be_success

        first_fee = result.fees[0]

        aggregate_failures do
          expect(first_fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            add_on_id: add_on_first.id,
            description: 'desc-123',
            unit_amount_cents: 1200,
            precise_unit_amount: 12,
            units: 2,
            amount_cents: 2400,
            amount_currency: 'EUR',
            fee_type: 'add_on',
            payment_status: 'pending',
          )
          expect(first_fee.taxes.map(&:code)).to contain_exactly(tax2.code)
        end
      end
    end
  end
end
