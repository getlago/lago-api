# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentRequests::Payments::AdyenCreateJob, type: :job do
  let(:payment_request) { create(:payment_request) }

  let(:adyen_service) { instance_double(PaymentRequests::Payments::AdyenService) }

  it 'calls the stripe create service' do
    allow(PaymentRequests::Payments::AdyenService).to receive(:new)
      .with(payment_request)
      .and_return(adyen_service)
    allow(adyen_service).to receive(:create)
      .and_return(BaseService::Result.new)

    described_class.perform_now(payment_request)

    expect(PaymentRequests::Payments::AdyenService).to have_received(:new)
    expect(adyen_service).to have_received(:create)
  end
end
