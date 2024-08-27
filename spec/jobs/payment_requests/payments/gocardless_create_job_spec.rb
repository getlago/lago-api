# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentRequests::Payments::GocardlessCreateJob, type: :job do
  let(:payment_request) { create(:payment_request) }

  let(:gocardless_service) { instance_double(PaymentRequests::Payments::GocardlessService) }

  it 'calls the stripe create service' do
    allow(PaymentRequests::Payments::GocardlessService).to receive(:new)
      .with(payment_request)
      .and_return(gocardless_service)
    allow(gocardless_service).to receive(:create)
      .and_return(BaseService::Result.new)

    described_class.perform_now(payment_request)

    expect(PaymentRequests::Payments::GocardlessService).to have_received(:new)
    expect(gocardless_service).to have_received(:create)
  end
end
