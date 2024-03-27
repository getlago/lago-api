# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::RefreshWebhookJob, type: :job do
  let(:stripe_service) { instance_double(PaymentProviders::StripeService) }
  let(:result) { BaseService::Result.new }

  let(:stripe_provider) { create(:stripe_provider) }

  before do
    allow(PaymentProviders::StripeService).to receive(:new)
      .and_return(stripe_service)
    allow(stripe_service).to receive(:refresh_webhook)
      .and_return(result)
  end

  it "calls the register webhook service" do
    described_class.perform_now(stripe_provider)

    expect(PaymentProviders::StripeService).to have_received(:new)
    expect(stripe_service).to have_received(:refresh_webhook)
  end
end
