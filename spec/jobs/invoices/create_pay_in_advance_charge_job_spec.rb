# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CreatePayInAdvanceChargeJob, type: :job do
  let(:charge) { create(:standard_charge, :pay_in_advance, invoiceable: true) }
  let(:event) { create(:event) }
  let(:timestamp) { Time.current.to_i }

  let(:invoice_service) { instance_double(Invoices::CreatePayInAdvanceChargeService) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::CreatePayInAdvanceChargeService).to receive(:new)
      .with(charge:, event:, timestamp:, invoice: nil)
      .and_return(invoice_service)
    allow(invoice_service).to receive(:call)
      .and_return(result)
  end

  it 'calls the create pay in advance charge service' do
    described_class.perform_now(charge:, event:, timestamp:)

    expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:new)
    expect(invoice_service).to have_received(:call)
  end

  context 'when result is a failure' do
    let(:result) do
      BaseService::Result.new.single_validation_failure!(error_code: 'error')
    end

    it 'raises an error' do
      expect do
        described_class.perform_now(charge:, event:, timestamp:)
      end.to raise_error(BaseService::FailedResult)

      expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:new)
      expect(invoice_service).to have_received(:call)
    end

    context 'with a previously created invoice' do
      let(:invoice) { create(:invoice, :generating) }

      it 'raises an error' do
        expect do
          described_class.perform_now(charge:, event:, timestamp:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:new)
        expect(invoice_service).to have_received(:call)
      end
    end

    context 'when a generating invoice is attached to the result' do
      let(:invoice) { create(:invoice, :generating) }

      before { result.invoice = invoice }

      it 'retries the job with the invoice' do
        described_class.perform_now(charge:, event:, timestamp:)

        expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:new)
        expect(invoice_service).to have_received(:call)

        expect(described_class).to have_been_enqueued
          .with(charge:, event:, timestamp:, invoice:)
      end
    end

    context 'when a not generating invoice is attached to the result' do
      let(:invoice) { create(:invoice, :draft) }

      before { result.invoice = invoice }

      it 'raises an error' do
        expect do
          described_class.perform_now(charge:, event:, timestamp:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::CreatePayInAdvanceChargeService).to have_received(:new)
        expect(invoice_service).to have_received(:call)
      end
    end
  end
end
