# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::Stripe::RegisterWebhookJob, type: :job do
  let(:result) { BaseService::Result.new }

  let(:stripe_provider) { create(:stripe_provider) }

  before do
    allow(PaymentProviders::Stripe::RegisterWebhookService).to receive(:call)
      .and_return(result)
  end

  it 'calls the register webhook service' do
    described_class.perform_now(stripe_provider)

    expect(PaymentProviders::Stripe::RegisterWebhookService).to have_received(:call)
  end
end
