# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::PaidCreditService do
  subject(:paid_credit_service) do
    described_class.new(invoice: invoice, customer: customer, wallet_transaction: wallet_transaction)
  end

  let(:customer) { create(:customer) }
  let(:invoice) { create(:invoice, organization: customer.organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:wallet) { create(:wallet, customer: customer) }
  let(:wallet_transaction) do
    create(:wallet_transaction, wallet: wallet, amount: '15.00', credit_amount: '15.00')
  end

  before { subscription }

  describe '.create' do
    it 'creates a fee' do
      result = paid_credit_service.create

      expect(result).to be_success

      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.id).not_to be_nil
        expect(created_fee.fee_type).to eq('credit')
        expect(created_fee.invoice_id).to eq(invoice.id)
        expect(created_fee.invoiceable_type).to eq('WalletTransaction')
        expect(created_fee.invoiceable_id).to eq(wallet_transaction.id)
        expect(created_fee.amount_cents).to eq(1500)
        expect(created_fee.amount_currency).to eq('EUR')
        expect(created_fee.vat_amount_cents).to eq(0)
        expect(created_fee.vat_rate).to eq(0)
        expect(created_fee.units).to eq(1)
        expect(created_fee.payment_status).to eq('pending')
      end
    end

    context 'when fee already exists on the period' do
      before do
        create(
          :fee,
          invoiceable_type: 'WalletTransaction',
          invoiceable_id: wallet_transaction.id,
          invoice: invoice,
        )
      end

      it 'does not create a new fee' do
        expect { paid_credit_service.create }.not_to change(Fee, :count)
      end
    end
  end
end
