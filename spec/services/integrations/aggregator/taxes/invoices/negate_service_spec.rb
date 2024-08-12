# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Taxes::Invoices::NegateService do
  subject(:service_call) { described_class.call(invoice:) }

  let(:integration) { create(:anrok_integration, organization:) }
  let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { 'https://api.nango.dev/v1/anrok/negate_invoices' }
  let(:current_time) { Time.current }

  let(:integration_collection_mapping1) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :fallback_item,
      settings: {external_id: '1', external_account_code: '11', external_name: ''}
    )
  end

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:
    )
  end

  let(:headers) do
    {
      'Connection-Id' => integration.connection_id,
      'Authorization' => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      'Provider-Config-Key' => 'anrok'
    }
  end

  let(:params) do
    [
      {
        'id' => invoice.id,
        'voided_id' => "#{invoice.id}_voided"
      }
    ]
  end

  before do
    allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)

    integration_customer
    integration_collection_mapping1
  end

  describe '#call' do
    context 'when service call is successful' do
      let(:response) { instance_double(Net::HTTPOK) }

      before do
        allow(lago_client).to receive(:post_with_response).with(params, headers).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      context 'when negate invoice sync is successful' do
        let(:body) do
          path = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response_negate.json')
          File.read(path)
        end

        it 'returns invoice_id' do
          result = service_call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice_id).to be_present
          end
        end
      end

      context 'when negate invoice sync is NOT successful' do
        let(:body) do
          path = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
          File.read(path)
        end

        it 'returns errors' do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ServiceFailure)
            expect(result.error.code).to eq('taxDateTooFarInFuture')
          end
        end

        it 'delivers an error webhook' do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              'customer.tax_provider_error',
              customer,
              provider: 'anrok',
              provider_code: integration.code,
              provider_error: {
                message: 'Service failure',
                error_code: 'taxDateTooFarInFuture'
              }
            )
        end
      end
    end

    context 'when service call is not successful' do
      let(:body) do
        path = Rails.root.join('spec/fixtures/integration_aggregator/error_response.json')
        File.read(path)
      end

      let(:http_error) { LagoHttpClient::HttpError.new(error_code, body, nil) }

      before do
        allow(lago_client).to receive(:post_with_response).with(params, headers).and_raise(http_error)
      end

      context 'when it is a server error' do
        let(:error_code) { Faker::Number.between(from: 500, to: 599) }

        it 'returns an error' do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.fees).to be(nil)
            expect(result.error).to be_a(BaseService::ServiceFailure)
            expect(result.error.code).to eq('action_script_runtime_error')
          end
        end
      end
    end
  end
end
