# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Taxes::Invoices::CreateService do
  subject(:service_call) { described_class.call(invoice:) }

  let(:integration) { create(:anrok_integration, organization:) }
  let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { 'https://api.nango.dev/v1/anrok/finalized_invoices' }
  let(:add_on) { create(:add_on, organization:) }
  let(:add_on_two) { create(:add_on, organization:) }
  let(:current_time) { Time.current }

  let(:integration_collection_mapping1) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :fallback_item,
      settings: {external_id: '1', external_account_code: '11', external_name: ''}
    )
  end
  let(:integration_mapping_add_on) do
    create(
      :netsuite_mapping,
      integration:,
      mappable_type: 'AddOn',
      mappable_id: add_on.id,
      settings: {external_id: 'm1', external_account_code: 'm11', external_name: ''}
    )
  end

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:
    )
  end
  let(:fee_add_on) do
    create(
      :fee,
      invoice:,
      add_on:,
      created_at: current_time - 3.seconds
    )
  end
  let(:fee_add_on_two) do
    create(
      :fee,
      invoice:,
      add_on: add_on_two,
      created_at: current_time - 2.seconds
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
        'issuing_date' => invoice.issuing_date,
        'currency' => invoice.currency,
        'contact' => {
          'external_id' => customer.external_id,
          'name' => customer.name,
          'address_line_1' => customer.shipping_address_line1,
          'city' => customer.shipping_city,
          'zip' => customer.shipping_zipcode,
          'country' => customer.shipping_country,
          'taxable' => false,
          'tax_number' => nil
        },
        'fees' => [
          {
            'item_id' => fee_add_on.item_id,
            'item_code' => 'm1',
            'amount_cents' => 200
          },
          {
            'item_id' => fee_add_on_two.item_id,
            'item_code' => '1',
            'amount_cents' => 200
          }
        ]
      }
    ]
  end

  before do
    allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)

    integration_customer
    integration_collection_mapping1
    integration_mapping_add_on
    fee_add_on
    fee_add_on_two
  end

  describe '#call' do
    context 'when service call is successful' do
      let(:response) { instance_double(Net::HTTPOK) }

      before do
        allow(lago_client).to receive(:post_with_response).with(params, headers).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      context 'when taxes are successfully fetched for finalized invoice' do
        let(:body) do
          path = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response.json')
          File.read(path)
        end

        it 'returns fees' do
          result = service_call

          aggregate_failures do
            expect(result).to be_success
            expect(result.fees.first['tax_breakdown'].first['rate']).to eq('0.10')
            expect(result.fees.first['tax_breakdown'].first['name']).to eq('GST/HST')
            expect(result.fees.first['tax_breakdown'].last['name']).to eq('reverseCharge')
            expect(result.fees.first['tax_breakdown'].last['type']).to eq('exempt')
            expect(result.fees.first['tax_breakdown'].last['rate']).to eq('0.00')
          end
        end
      end

      context 'when taxes are not successfully fetched for finalized invoice' do
        let(:body) do
          path = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
          File.read(path)
        end

        it 'does not return fees' do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.fees).to be(nil)
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
