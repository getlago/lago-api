# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Contacts::UpdateService do
  subject(:service_call) { described_class.call(integration:, integration_customer:) }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { 'https://api.nango.dev/v1/netsuite/contacts' }

  let(:headers) do
    {
      'Connection-Id' => integration.connection_id,
      'Authorization' => "Bearer #{ENV['NANGO_SECRET_KEY']}",
      'Provider-Config-Key' => 'netsuite',
    }
  end

  let(:params) do
    {
      'type' => 'customer',
      'recordId' => integration_customer.external_customer_id,
      'values' => {
        'companyname' => customer.name,
        'subsidiary' => integration_customer.subsidiary_id,
        'custentity_form_activeprospect_customer' => customer.name,
        'email' => customer.email,
        'phone' => customer.phone,
      },
      'options': {
        'isDynamic' => false,
      },
    }
  end

  before do
    allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
  end

  describe '#call' do
    context 'when service call is successful' do
      let(:response) { instance_double(Net::HTTPOK) }
      let(:code) { 200 }

      let(:body) do
        path = Rails.root.join('spec/fixtures/integration_aggregator/contacts/success_response.json')
        File.read(path).to_i.to_s
      end

      before do
        allow(lago_client).to receive(:put_with_response).with(params, headers).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      it 'returns contact id' do
        result = service_call

        aggregate_failures do
          expect(result).to be_success
          expect(result.contact_id).to eq('1')
        end
      end
    end

    context 'when service call is not successful' do
      let(:body) do
        path = Rails.root.join('spec/fixtures/integration_aggregator/contacts/error_response.json')
        File.read(path)
      end

      let(:http_error) { LagoHttpClient::HttpError.new(500, body, nil) }

      before do
        allow(lago_client).to receive(:put_with_response).with(params, headers).and_raise(http_error)
      end

      it 'returns an error' do
        result = service_call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq('action_script_runtime_error')
          expect(result.error.message)
            .to eq('action_script_runtime_error: submitFields: Missing a required argument: type')
        end
      end

      it 'delivers an error webhook' do
        expect { service_call }.to enqueue_job(SendWebhookJob)
          .with(
            'customer.accounting_provider_error',
            customer,
            provider: 'netsuite',
            provider_error: {
              message: 'submitFields: Missing a required argument: type',
              error_code: 'action_script_runtime_error',
            },
          )
      end
    end
  end
end
