# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Invoices::Crm::UpdateService do
  subject(:service_call) { service.call }

  let(:service) { described_class.new(invoice:) }
  let(:integration) { create(:hubspot_integration, organization:) }
  let(:integration_customer) { create(:hubspot_customer, integration:, customer:) }
  let(:integration_invoice) { create(:integration_resource, syncable: invoice, integration:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { 'https://api.nango.dev/v1/hubspot/records' }
  let(:invoice_file_url) { invoice.file_url }
  let(:file_url) { Faker::Internet.url }
  let(:due_date) { invoice.payment_due_date.strftime('%Y-%m-%d') }

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      coupons_amount_cents: 2000,
      prepaid_credit_amount_cents: 4000,
      credit_notes_amount_cents: 6000,
      taxes_amount_cents: 8000
    )
  end

  let(:headers) do
    {
      'Connection-Id' => integration.connection_id,
      'Authorization' => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      'Provider-Config-Key' => 'hubspot'
    }
  end

  let(:params) do
    service.__send__(:payload).update_body
  end

  before do
    allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
    allow(invoice).to receive(:file_url).and_return(file_url)

    integration_customer
    integration.sync_invoices = true
    integration.save!
  end

  describe '#call_async' do
    subject(:service_call_async) { described_class.new(invoice:).call_async }

    context 'when invoice exists' do
      it 'enqueues invoice update job' do
        expect { service_call_async }.to enqueue_job(Integrations::Aggregator::Invoices::Crm::UpdateJob)
      end
    end

    context 'when invoice does not exist' do
      let(:invoice) { nil }

      it 'returns an error' do
        result = service_call_async

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('invoice_not_found')
        end
      end
    end
  end

  describe '#call' do
    before { integration_invoice }

    context 'when sync_invoices is false' do
      before { integration.update!(sync_invoices: false) }

      it 'does not return external id' do
        result = service_call

        aggregate_failures do
          expect(result).to be_success
          expect(result.external_id).to be(nil)
        end
      end
    end

    context 'when sync_invoices is true' do
      context 'when service call is successful' do
        let(:response) { instance_double(Net::HTTPOK) }

        before do
          allow(lago_client).to receive(:put_with_response).with(params, headers).and_return(response)
          allow(response).to receive(:body).and_return(body)
        end

        context 'when invoice is succesfully updated' do
          let(:body) do
            path = Rails.root.join('spec/fixtures/integration_aggregator/invoices/crm/success_hash_response.json')
            File.read(path)
          end

          it 'returns external id' do
            result = service_call

            aggregate_failures do
              expect(result).to be_success
              expect(result.external_id).to eq('123456789')
            end
          end
        end

        context 'when invoice is not updated' do
          let(:body) do
            path = Rails.root.join('spec/fixtures/integration_aggregator/invoices/crm/failure_hash_response.json')
            File.read(path)
          end

          it 'does not return external id' do
            result = service_call

            aggregate_failures do
              expect(result).to be_success
              expect(result.external_id).to be(nil)
            end
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
          allow(lago_client).to receive(:put_with_response).with(params, headers).and_raise(http_error)
        end

        context 'when it is a server error' do
          let(:error_code) { Faker::Number.between(from: 500, to: 599) }

          it 'does not return an error' do
            expect { service_call }.not_to raise_error
          end

          it 'enqueues a SendWebhookJob' do
            expect { service_call }.to have_enqueued_job(SendWebhookJob)
          end
        end

        context 'when it is a client error' do
          let(:error_code) { Faker::Number.between(from: 400, to: 499) }

          it 'does not return an error' do
            expect { service_call }.not_to raise_error
          end

          it 'returns result' do
            expect(service_call).to be_a(BaseService::Result)
          end

          it 'enqueues a SendWebhookJob' do
            expect { service_call }.to have_enqueued_job(SendWebhookJob)
          end
        end
      end
    end
  end
end
