# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Contacts::CreateService do
  subject(:service_call) { described_class.call(integration:, customer:, subsidiary_id:) }

  let(:customer) { create(:customer, organization:) }
  let(:subsidiary_id) { '1' }
  let(:organization) { create(:organization) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { "https://api.nango.dev/v1/#{integration_type}/contacts" }

  let(:headers) do
    {
      'Connection-Id' => integration.connection_id,
      'Authorization' => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      'Provider-Config-Key' => integration_type_key
    }
  end

  let(:customer_link) do
    url = ENV["LAGO_FRONT_URL"].presence || "https://app.getlago.com"

    URI.join(url, "/customer/", customer.id).to_s
  end

  before do
    allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
  end

  describe '#call' do
    context 'when service call is successful' do
      let(:response) { instance_double(Net::HTTPOK) }

      before do
        allow(lago_client).to receive(:post_with_response).with(params, headers).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      context 'when response is a string' do
        let(:integration) { create(:netsuite_integration, organization:) }
        let(:integration_type) { 'netsuite' }
        let(:integration_type_key) { 'netsuite-tba' }

        let(:params) do
          {
            'type' => 'customer',
            'isDynamic' => false,
            'columns' => {
              'companyname' => customer.name,
              'subsidiary' => subsidiary_id,
              'custentity_lago_id' => customer.id,
              'custentity_lago_sf_id' => customer.external_salesforce_id,
              'custentity_form_activeprospect_customer' => customer.name,
              'custentity_lago_customer_link' => customer_link,
              'email' => customer.email,
              'phone' => customer.phone
            },
            'options' => {
              'ignoreMandatoryFields' => false
            }
          }
        end

        let(:body) do
          path = Rails.root.join('spec/fixtures/integration_aggregator/contacts/success_string_response.json')
          File.read(path)
        end

        it 'returns contact id' do
          result = service_call

          aggregate_failures do
            expect(result).to be_success
            expect(result.contact_id).to eq('1')
          end
        end

        it 'delivers a success webhook' do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              'customer.accounting_provider_created',
              customer
            ).on_queue(:webhook)
        end
      end

      context 'when response is a hash' do
        let(:integration) { create(:xero_integration, organization:) }
        let(:integration_type) { 'xero' }
        let(:integration_type_key) { 'xero' }

        let(:params) do
          [
            {
              'name' => customer.name,
              'email' => customer.email,
              'city' => customer.city,
              'zip' => customer.zipcode,
              'country' => customer.country,
              'state' => customer.state,
              'phone' => customer.phone
            }
          ]
        end

        context 'when contact is succesfully created' do
          let(:body) do
            path = Rails.root.join('spec/fixtures/integration_aggregator/contacts/success_hash_response.json')
            File.read(path)
          end

          it 'returns contact id' do
            result = service_call

            aggregate_failures do
              expect(result).to be_success
              expect(result.contact_id).to eq('2e50c200-9a54-4a66-b241-1e75fb87373f')
            end
          end

          it 'delivers a success webhook' do
            expect { service_call }.to enqueue_job(SendWebhookJob)
              .with(
                'customer.accounting_provider_created',
                customer
              ).on_queue(:webhook)
          end
        end

        context 'when contact is not created' do
          let(:body) do
            path = Rails.root.join('spec/fixtures/integration_aggregator/contacts/failure_hash_response.json')
            File.read(path)
          end

          it 'does not return contact id' do
            result = service_call

            aggregate_failures do
              expect(result).to be_success
              expect(result.contact).to be(nil)
            end
          end

          it 'does not create integration resource object' do
            expect { service_call }.not_to change(IntegrationResource, :count)
          end
        end
      end
    end

    context 'when service call is not successful' do
      let(:integration) { create(:netsuite_integration, organization:) }
      let(:integration_type) { 'netsuite' }
      let(:integration_type_key) { 'netsuite-tba' }

      let(:params) do
        {
          'type' => 'customer',
          'isDynamic' => false,
          'columns' => {
            'companyname' => customer.name,
            'subsidiary' => subsidiary_id,
            'custentity_lago_id' => customer.id,
            'custentity_lago_sf_id' => customer.external_salesforce_id,
            'custentity_form_activeprospect_customer' => customer.name,
            'custentity_lago_customer_link' => customer_link,
            'email' => customer.email,
            'phone' => customer.phone
          },
          'options' => {
            'ignoreMandatoryFields' => false
          }
        }
      end

      let(:http_error) { LagoHttpClient::HttpError.new(error_code, body, nil) }

      before do
        allow(lago_client).to receive(:post_with_response).with(params, headers).and_raise(http_error)
      end

      context 'when it is a server error' do
        let(:error_code) { Faker::Number.between(from: 500, to: 599) }
        let(:code) { 'action_script_runtime_error' }
        let(:message) { 'submitFields: Missing a required argument: type' }

        let(:body) do
          path = Rails.root.join('spec/fixtures/integration_aggregator/error_response.json')
          File.read(path)
        end

        it 'returns an error' do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error.code).to eq(code)
            expect(result.error.message).to eq("#{code}: #{message}")
          end
        end

        it 'delivers an error webhook' do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              'customer.accounting_provider_error',
              customer,
              provider: 'netsuite',
              provider_code: integration.code,
              provider_error: {
                message:,
                error_code: code
              }
            )
        end
      end

      context 'when it is a client error' do
        let(:error_code) { 404 }
        let(:code) { 'invalid_secret_key_format' }
        let(:message) { 'Authentication failed. The provided secret key is not a UUID v4.' }

        let(:body) do
          path = Rails.root.join('spec/fixtures/integration_aggregator/error_auth_response.json')
          File.read(path)
        end

        it 'returns an error' do
          result = service_call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error.code).to eq(code)
            expect(result.error.message).to eq("#{code}: #{message}")
          end
        end

        it 'delivers an error webhook' do
          expect { service_call }.to enqueue_job(SendWebhookJob)
            .with(
              'customer.accounting_provider_error',
              customer,
              provider: 'netsuite',
              provider_code: integration.code,
              provider_error: {
                message:,
                error_code: code
              }
            )
        end
      end
    end
  end
end
