# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::PaymentProviders::CustomerErrorService do
  subject(:webhook_service) { described_class.new(object: customer, options: webhook_options) }

  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization, webhook_url:) }
  let(:webhook_url) { 'http://foo.bar' }

  let(:webhook_options) { { provider_error: { message: 'message', error_code: 'code' } } }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post)
    end

    it 'calls the organization webhook url' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post)
    end

    it 'builds payload with customer.payment_provider_error webhook type' do
      webhook_service.call

      aggregate_failures do
        expect(LagoHttpClient::Client).to have_received(:new)
          .with(organization.webhook_url)
        expect(lago_client).to have_received(:post) do |payload|
          expect(payload[:webhook_type]).to eq('customer.payment_provider_error')
          expect(payload[:object_type]).to eq('payment_provider_customer_error')
        end
      end
    end
  end
end
