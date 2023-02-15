# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::Events::ErrorService do
  subject(:webhook_service) { described_class.new(object:) }

  let(:organization) { create(:organization, webhook_url:) }
  let(:webhook_url) { 'http://foo.bar' }
  let(:object) do
    {
      input_params: {
        external_customer_id: 'customer',
        transaction_id: SecureRandom.uuid,
        code: 'code',
      },
      error: 'Code does not exist',
      organization_id: organization.id,
    }
  end

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it 'builds payload with event.error webhook type' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq('event.error')
        expect(payload[:object_type]).to eq('event_error')
      end
    end
  end
end
