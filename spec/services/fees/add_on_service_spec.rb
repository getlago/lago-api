# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::AddOnService do
  subject(:add_on_service) do
    described_class.new(invoice:, applied_add_on:)
  end

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:applied_add_on) { create(:applied_add_on, customer:) }

  let(:tax) { create(:tax, rate: 20, organization:) }

  before { tax }

  describe '.create' do
    it 'creates a fee' do
      result = add_on_service.create

      expect(result).to be_success

      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.id).not_to be_nil
        expect(created_fee.invoice_id).to eq(invoice.id)
        expect(created_fee.applied_add_on_id).to eq(applied_add_on.id)
        expect(created_fee.amount_cents).to eq(200)
        expect(created_fee.amount_currency).to eq('EUR')
        expect(created_fee.units).to eq(1)
        expect(created_fee.events_count).to be_nil
        expect(created_fee.payment_status).to eq('pending')

        expect(created_fee.taxes_amount_cents).to eq(40)
        expect(created_fee.taxes_rate).to eq(20.0)
        expect(created_fee.applied_taxes.count).to eq(1)
      end
    end

    context 'when fee already exists on the period' do
      before do
        create(
          :fee,
          applied_add_on:,
          invoice:,
        )
      end

      it 'does not create a new fee' do
        expect { add_on_service.create }.not_to change(Fee, :count)
      end
    end
  end
end
