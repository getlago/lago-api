# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::CreditNotes::PaymentProviderRefundFailureService do
  subject(:webhook_service) { described_class.new(object: credit_note, options: webhook_options) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:credit_note) { create(:credit_note, customer:, invoice:) }
  let(:webhook_options) { {provider_error: {message: 'message', error_code: 'code'}} }

  describe '.call' do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it 'builds payload with credit_note.refund_failure webhook type' do
      webhook_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(organization.webhook_endpoints.first.webhook_url)
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:webhook_type]).to eq('credit_note.refund_failure')
        expect(payload[:object_type]).to eq('credit_note_payment_provider_refund_error')
      end
    end
  end
end
