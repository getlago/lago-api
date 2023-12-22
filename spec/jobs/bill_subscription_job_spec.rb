# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillSubscriptionJob, type: :job do
  let(:subscriptions) { [create(:subscription)] }
  let(:timestamp) { Time.zone.now.to_i }

  let(:invoice) { nil }
  let(:recurring) { false }
  let(:result) { BaseService::Result.new }

  before do
    allow(Invoices::SubscriptionService).to receive(:call)
      .with(subscriptions:, timestamp:, recurring:, invoice:)
      .and_return(result)
  end

  it 'calls the invoices create service' do
    described_class.perform_now(subscriptions, timestamp)

    expect(Invoices::SubscriptionService).to have_received(:call)
  end

  context 'when result is a failure' do
    let(:result) do
      BaseService::Result.new.single_validation_failure!(error_code: 'error')
    end

    it 'raises an error' do
      expect do
        described_class.perform_now(subscriptions, timestamp)
      end.to raise_error(BaseService::FailedResult)

      expect(Invoices::SubscriptionService).to have_received(:call)
    end

    context 'with a previously created invoice' do
      let(:invoice) { create(:invoice, :generating) }

      it 'raises an error' do
        expect do
          described_class.perform_now(subscriptions, timestamp, invoice:)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::SubscriptionService).to have_received(:call)
      end
    end

    context 'when a generating invoice is attached to the result' do
      let(:result_invoice) { create(:invoice, :generating) }

      before { result.invoice = result_invoice }

      it 'retries the job with the invoice' do
        described_class.perform_now(subscriptions, timestamp)

        expect(Invoices::SubscriptionService).to have_received(:call)

        expect(described_class).to have_been_enqueued
          .with(subscriptions, timestamp, recurring: false, invoice: result_invoice)
      end
    end

    context 'when a not generating invoice is attached to the result' do
      let(:result_invoice) { create(:invoice, :draft) }

      before { result.invoice = result_invoice }

      it 'raises an error' do
        expect do
          described_class.perform_now(subscriptions, timestamp)
        end.to raise_error(BaseService::FailedResult)

        expect(Invoices::SubscriptionService).to have_received(:call)
      end
    end
  end
end
