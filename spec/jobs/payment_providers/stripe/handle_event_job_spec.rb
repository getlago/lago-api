# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::HandleEventJob, type: :job do
  let(:stripe_service) { instance_double(PaymentProviders::StripeService) }
  let(:result) { BaseService::Result.new }
  let(:organization) { create(:organization) }

  let(:stripe_event) do
    {}
  end

  before do
    allow(PaymentProviders::StripeService).to receive(:new)
      .and_return(stripe_service)
    allow(stripe_service).to receive(:handle_event)
      .and_return(result)
  end

  it "calls the handle event service" do
    described_class.perform_now(
      organization:,
      event: stripe_event
    )

    expect(PaymentProviders::StripeService).to have_received(:new)
    expect(stripe_service).to have_received(:handle_event)
  end
end
