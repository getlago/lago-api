# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::Invoices::Payloads::Netsuite do
  describe '#body' do
    subject(:body_call) { payload.body }

    let(:payload) { described_class.new(integration_customer:, invoice:) }
    let(:integration_customer) { FactoryBot.create(:xero_customer, integration:, customer:) }
    let(:integration) { create(:netsuite_integration, organization:) }
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }
    let(:add_on) { create(:add_on, organization:) }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:charge) { create(:standard_charge, billable_metric:) }
    let(:current_time) { Time.current }

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
        taxes_amount_cents: 200,
        issuing_date: DateTime.new(2024, 7, 8)
      )
    end

    let(:fee_sub) do
      create(
        :fee,
        invoice:,
        amount_cents: 10_000,
        taxes_amount_cents: 200,
        created_at: current_time - 3.seconds
      )
    end

    let(:minimum_commitment_fee) do
      create(
        :minimum_commitment_fee,
        invoice:,
        created_at: current_time - 2.seconds
      )
    end

    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        charge:,
        units: 2,
        precise_unit_amount: 4.12121212123337777,
        created_at: current_time
      )
    end

    let(:invoice_link) do
      url = ENV["LAGO_FRONT_URL"].presence || "https://app.getlago.com"

      URI.join(url, "/customer/#{customer.id}/", "invoice/#{invoice.id}/overview").to_s
    end

    let(:due_date) { invoice.payment_due_date.strftime("%-m/%-d/%Y") }

    let(:body) do
      {
        'type' => 'invoice',
        'isDynamic' => true,
        'columns' => {
          'tranid' => invoice.id,
          'entity' => integration_customer.external_customer_id,
          'istaxable' => true,
          'taxitem' => integration_collection_mapping5.external_id,
          'taxamountoverride' => 2.0,
          'otherrefnum' => invoice.number,
          'custbody_lago_id' => invoice.id,
          'custbody_ava_disable_tax_calculation' => true,
          'custbody_lago_invoice_link' => invoice_link,
          'duedate' => due_date
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
                'rate' => 4.1212121212334
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
    end

    it 'returns payload body' do
      expect(subject).to eq(body)
    end
  end
end
