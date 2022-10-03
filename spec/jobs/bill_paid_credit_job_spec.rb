# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillPaidCreditJob, type: :job do
  let(:wallet_transaction) { create(:wallet_transaction) }
  let(:timestamp) { Time.current.to_i }

  let(:invoice_service) { instance_double(Invoices::PaidCreditService) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::PaidCreditService).to receive(:new)
      .with(wallet_transaction: wallet_transaction, timestamp: timestamp)
      .and_return(invoice_service)
    allow(invoice_service).to receive(:create)
      .and_return(result)
  end

  it 'calls the paid credit service create method' do
    described_class.perform_now(wallet_transaction, timestamp)

    expect(Invoices::PaidCreditService).to have_received(:new)
    expect(invoice_service).to have_received(:create)
  end

  context 'when result is a failure' do
    let(:result) do
      BaseService::Result.new.single_validation_failure!(error_code: 'error')
    end

    it 'raises an error' do
      expect do
        described_class.perform_now(wallet_transaction, timestamp)
      end.to raise_error(BaseService::FailedResult)

      expect(Invoices::PaidCreditService).to have_received(:new)
      expect(invoice_service).to have_received(:create)
    end
  end
end
