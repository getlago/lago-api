# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::PaymentProviders::InvoicePaymentFailureService do
  subject(:webhook_service) { described_class.new(object: invoice, options: webhook_options) }

  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:organization) { create(:organization) }
  let(:webhook_options) { {provider_error: {message: 'message', error_code: 'code'}} }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it 'builds payload with invoice.payment_failure webhook type' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq('invoice.payment_failure')
        expect(payload[:object_type]).to eq('payment_provider_invoice_payment_error')
      end
    end
  end
end
