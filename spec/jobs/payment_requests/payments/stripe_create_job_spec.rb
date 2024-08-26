# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentRequests::Payments::StripeCreateJob, type: :job do
  let(:payment_request) { create(:payment_request) }

  let(:stripe_service) { instance_double(PaymentRequests::Payments::StripeService) }

  it 'calls the stripe create service' do
    allow(PaymentRequests::Payments::StripeService).to receive(:new)
      .with(payment_request)
      .and_return(stripe_service)
    allow(stripe_service).to receive(:create)
      .and_return(BaseService::Result.new)

    described_class.perform_now(payment_request)

    expect(PaymentRequests::Payments::StripeService).to have_received(:new)
    expect(stripe_service).to have_received(:create)
  end
end
