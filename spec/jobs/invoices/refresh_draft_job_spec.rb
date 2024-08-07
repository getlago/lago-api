# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::RefreshDraftJob, type: :job do
  let(:invoice) { create(:invoice) }
  let(:result) { BaseService::Result.new }

  let(:refresh_service) do
    instance_double(Invoices::RefreshDraftService)
  end

  it 'delegates to the RefreshDraft service' do
    allow(Invoices::RefreshDraftService).to receive(:new).with(invoice:).and_return(refresh_service)
    allow(refresh_service).to receive(:call).and_return(result)

    described_class.perform_now(invoice)

    expect(Invoices::RefreshDraftService).to have_received(:new)
    expect(refresh_service).to have_received(:call)
  end

  context 'when there was a tax fetching error in RefreshDraft service' do
    let(:integration_customer) { create(:anrok_customer, customer: invoice.customer) }
    let(:response) { instance_double(Net::HTTPOK) }
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:endpoint) { 'https://api.nango.dev/v1/anrok/finalized_invoices' }
    let(:integration_collection_mapping) do
      create(
        :netsuite_collection_mapping,
        integration: integration_customer.integration,
        mapping_type: :fallback_item,
        settings: {external_id: '1', external_account_code: '11', external_name: ''}
      )
    end
    let(:body) do
      p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
      File.read(p)
    end

    before do
      integration_collection_mapping

      allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
      allow(lago_client).to receive(:post_with_response).and_return(response)
      allow(response).to receive(:body).and_return(body)
    end

    it 'does not throw an error when it is a tax error' do
      expect { described_class.perform_now(invoice) }.not_to raise_error
    end
  end
end
