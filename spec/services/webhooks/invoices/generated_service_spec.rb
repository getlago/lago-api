# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Invoices::GeneratedService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:webhook_endpoint) { create(:webhook_endpoint, webhook_url:) }
  let(:organization) { webhook_endpoint.organization.reload }
  let(:webhook_url) { 'http://foo.bar' }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(webhook_endpoint.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it 'builds payload with invoice.generated webhook type' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(webhook_endpoint.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq('invoice.generated')
        expect(payload[:object_type]).to eq('invoice')
        expect(payload['invoice'][:customer]).to be_present
      end
    end
  end
end
