# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillSubscriptionJob, type: :job do
  let(:subscription) { create(:subscription) }
  let(:timestamp) { Time.zone.now.to_i }

  let(:invoice_service) { instance_double(Invoices::SubscriptionService) }
  let(:result) { BaseService::Result.new }

  it 'calls the invoices create service' do
    allow(Invoices::SubscriptionService).to receive(:new)
      .with(subscriptions: [subscription], timestamp: timestamp, recurring: false)
      .and_return(invoice_service)
    allow(invoice_service).to receive(:create)
      .and_return(result)

    described_class.perform_now([subscription], timestamp)

    expect(Invoices::SubscriptionService).to have_received(:new)
    expect(invoice_service).to have_received(:create)
  end

  context 'when result is a failure' do
    let(:result) do
      BaseService::Result.new.single_validation_failure!(error_code: 'error')
    end

    it 'raises an error' do
      allow(Invoices::SubscriptionService).to receive(:new)
        .with(subscriptions: [subscription], timestamp: timestamp, recurring: false)
        .and_return(invoice_service)
      allow(invoice_service).to receive(:create)
        .and_return(result)

      expect do
        described_class.perform_now([subscription], timestamp)
      end.to raise_error(BaseService::FailedResult)

      expect(Invoices::SubscriptionService).to have_received(:new)
      expect(invoice_service).to have_received(:create)
    end
  end
end
