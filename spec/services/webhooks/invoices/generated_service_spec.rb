# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Invoices::GeneratedService do
  subject(:webhook_service) { described_class.new(invoice) }

  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, organization: organization, customer: customer) }
  let(:invoice) { create(:invoice, customer: customer) }
  let(:organization) { create(:organization, webhook_url: webhook_url) }
  let(:webhook_url) { 'http://foo.bar' }

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

    it 'builds payload with invoice.generated webhook type' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post) do |payload|
        expect(payload[:webhook_type]).to eq('invoice.generated')
        expect(payload[:object_type]).to eq('invoice')
      end
    end
  end
end
