# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Payments::CreateService do
  subject(:service_call) { described_class.call(payment:) }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { 'https://api.nango.dev/v1/netsuite/payments' }
  let(:payment) { create(:payment, invoice:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:integration_invoice) { create(:integration_resource, syncable: invoice, integration:) }

  let(:headers) do
    {
      'Connection-Id' => integration.connection_id,
      'Authorization' => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      'Provider-Config-Key' => 'netsuite'
    }
  end

  let(:params) do
    {
      'type' => 'customerpayment',
      'isDynamic' => true,
      'columns' => {
        'customer' => integration_customer.external_customer_id
      },
      'lines' => [
        {
          'sublistId' => 'apply',
          'lineItems' => [
            {
              'doc' => integration_invoice.external_id,
              'apply' => true,
              'amount' => payment.amount_cents.div(100).to_f
            }
          ]
        }
      ],
      'options' => {
        'ignoreMandatoryFields' => false
      }
    }
  end

  before do
    allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)

    integration_customer
    integration.sync_payments = true
    integration.save!
    integration_invoice
    payment
  end

  describe '#call_async' do
    subject(:service_call_async) { described_class.new(payment:).call_async }

    context 'when payment exists' do
      it 'enqueues payment create job' do
        expect { service_call_async }.to enqueue_job(Integrations::Aggregator::Payments::CreateJob)
      end
    end

    context 'when payment does not exist' do
      let(:payment) { nil }

      it 'returns an error' do
        result = service_call_async

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('payment_not_found')
        end
      end
    end
  end

  describe '#call' do
    context 'when service call is successful' do
      let(:response) { instance_double(Net::HTTPOK) }

      let(:body) do
        path = Rails.root.join('spec/fixtures/integration_aggregator/payments/success_response.json')
        File.read(path)
      end

      before do
        allow(lago_client).to receive(:post_with_response).with(params, headers).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      it 'returns external id' do
        result = service_call

        aggregate_failures do
          expect(result).to be_success
          expect(result.external_id).to eq('999')
        end
      end

      it 'creates integration resource object' do
        expect { service_call }.to change(IntegrationResource, :count).by(1)

        integration_resource = IntegrationResource.order(created_at: :desc).first

        expect(integration_resource.syncable_id).to eq(payment.id)
        expect(integration_resource.syncable_type).to eq('Payment')
        expect(integration_resource.resource_type).to eq('payment')
      end
    end

    context 'when service call is not successful' do
      let(:body) do
        path = Rails.root.join('spec/fixtures/integration_aggregator/error_response.json')
        File.read(path)
      end

      let(:http_error) { LagoHttpClient::HttpError.new(500, body, nil) }

      before do
        allow(lago_client).to receive(:post_with_response).with(params, headers).and_raise(http_error)
      end

      it 'returns an error' do
        expect { service_call }.to raise_error(http_error)
      end

      it 'enqueues a SendWebhookJob' do
        expect { service_call }
          .to have_enqueued_job(SendWebhookJob)
          .and raise_error(http_error)
      end
    end
  end
end
