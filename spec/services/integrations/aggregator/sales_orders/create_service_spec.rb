# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::SalesOrders::CreateService do
  subject(:service_call) { described_class.call(invoice:) }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:lago_client) { instance_double(LagoHttpClient::Client) }
  let(:endpoint) { 'https://api.nango.dev/v1/netsuite/salesorders' }
  let(:add_on) { create(:add_on, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:) }

  let(:integration_collection_mapping1) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :fallback_item,
      settings: {external_id: '1', external_account_code: '11', external_name: ''}
    )
  end
  let(:integration_collection_mapping2) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :coupon,
      settings: {external_id: '2', external_account_code: '22', external_name: ''}
    )
  end
  let(:integration_collection_mapping3) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :subscription_fee,
      settings: {external_id: '3', external_account_code: '33', external_name: ''}
    )
  end
  let(:integration_collection_mapping4) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :minimum_commitment,
      settings: {external_id: '4', external_account_code: '44', external_name: ''}
    )
  end
  let(:integration_collection_mapping5) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :tax,
      settings: {external_id: '5', external_account_code: '55', external_name: ''}
    )
  end
  let(:integration_collection_mapping6) do
    create(
      :netsuite_collection_mapping,
      integration:,
      mapping_type: :prepaid_credit,
      settings: {external_id: '6', external_account_code: '66', external_name: ''}
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
  let(:integration_mapping_bm) do
    create(
      :netsuite_mapping,
      integration:,
      mappable_type: 'BillableMetric',
      mappable_id: billable_metric.id,
      settings: {external_id: 'm2', external_account_code: 'm22', external_name: ''}
    )
  end

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
  let(:fee_sub) do
    create(
      :fee,
      invoice:
    )
  end
  let(:minimum_commitment_fee) do
    create(
      :minimum_commitment_fee,
      invoice:
    )
  end
  let(:charge_fee) do
    create(
      :charge_fee,
      invoice:,
      charge:,
      units: 2,
      precise_unit_amount: 4.12
    )
  end

  let(:headers) do
    {
      'Connection-Id' => integration.connection_id,
      'Authorization' => "Bearer #{ENV["NANGO_SECRET_KEY"]}",
      'Provider-Config-Key' => 'netsuite'
    }
  end

  let(:params) do
    {
      'type' => 'salesorder',
      'isDynamic' => true,
      'columns' => {
        'tranid' => invoice.id,
        'entity' => integration_customer.external_customer_id,
        'istaxable' => true,
        'taxitem' => integration_collection_mapping5.external_id,
        'taxamountoverride' => 80.0,
        'otherrefnum' => invoice.number,
        'custbody_lago_id' => invoice.id,
        'custbody_ava_disable_tax_calculation' => true
      },
      'lines' => [
        {
          'sublistId' => 'item',
          'lineItems' => [
            {
              'item' => '3',
              'account' => '33',
              'quantity' => 0.0,
              'rate' => 0.0
            },
            {
              'item' => '4',
              'account' => '44',
              'quantity' => 0.0,
              'rate' => 0.0
            },
            {
              'item' => 'm2',
              'account' => 'm22',
              'quantity' => 2,
              'rate' => 4.12
            },
            {
              'item' => '2',
              'account' => '22',
              'quantity' => 1,
              'rate' => -20.0
            },
            {
              'item' => '6',
              'account' => '66',
              'quantity' => 1,
              'rate' => -40.0
            },
            {
              'item' => '1', # Fallback item instead of credit note
              'account' => '11',
              'quantity' => 1,
              'rate' => -60.0
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
    charge
    integration_collection_mapping1
    integration_collection_mapping2
    integration_collection_mapping3
    integration_collection_mapping4
    integration_collection_mapping5
    integration_collection_mapping6
    integration_mapping_add_on
    integration_mapping_bm
    fee_sub
    minimum_commitment_fee
    charge_fee

    integration.sync_sales_orders = true
    integration.save!
  end

  describe '#call' do
    context 'when service call is successful' do
      let(:response) { instance_double(Net::HTTPOK) }

      let(:body) do
        path = Rails.root.join('spec/fixtures/integration_aggregator/invoices/success_response.json')
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
          expect(result.external_id).to eq('456')
        end
      end

      it 'creates integration resource object' do
        expect { service_call }
          .to change(IntegrationResource, :count).by(1)

        integration_resource = IntegrationResource.order(created_at: :desc).first

        expect(integration_resource.syncable_id).to eq(invoice.id)
        expect(integration_resource.syncable_type).to eq('Invoice')
        expect(integration_resource.resource_type).to eq('sales_order')
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
        expect do
          service_call
        end.to raise_error(http_error)
      end

      it 'enqueues a SendWebhookJob' do
        expect { service_call }
          .to have_enqueued_job(SendWebhookJob)
          .and raise_error(http_error)
      end
    end
  end
end
