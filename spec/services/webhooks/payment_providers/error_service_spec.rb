# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::PaymentProviders::ErrorService do
  subject(:webhook_service) { described_class.new(object: payment_provider, options: webhook_options) }

  let(:payment_provider) { create(:stripe_provider, organization:) }
  let(:organization) { create(:organization) }
  let(:webhook_options) { {provider_error: {message: 'message', error_code: 'code', source: 'stripe', action: 'payment_provider.register_webhook'}} }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it 'builds payload with payment_provider.error webhook type' do
      webhook_service.call

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new)
          .with(organization.webhook_endpoints.first.webhook_url)
        expect(lago_client).to have_received(:post_with_response) do |payload|
          expect(payload[:webhook_type]).to eq('payment_provider.error')
          expect(payload[:object_type]).to eq('payment_provider_error')
        end
      end
    end
  end
end
