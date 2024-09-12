# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::OneOffService do
  subject(:one_off_service) do
    described_class.new(invoice:, fees:)
  end

  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:) }
  let(:tax2) { create(:tax, organization:, applied_to_organization: false) }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:fees) do
    [
      {
        add_on_code: add_on_first.code,
        unit_amount_cents: 1200,
        units: 2,
        description: 'desc-123',
        tax_codes: [tax2.code]
      },
      {
        add_on_code: add_on_second.code
      }
    ]
  end

  before { tax }

  describe 'create' do
    before { CurrentContext.source = 'api' }

    it 'creates fees' do
      result = one_off_service.create

      expect(result).to be_success

      first_fee = result.fees[0]
      second_fee = result.fees[1]

      aggregate_failures do
        expect(first_fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          add_on_id: add_on_first.id,
          description: 'desc-123',
          unit_amount_cents: 1200,
          precise_unit_amount: 12,
          units: 2,
          amount_cents: 2400,
          precise_amount_cents: 2400.0,
          amount_currency: 'EUR',
          fee_type: 'add_on',
          payment_status: 'pending'
        )
        expect(first_fee.taxes.map(&:code)).to contain_exactly(tax2.code)

        expect(second_fee).to have_attributes(
          id: String,
          invoice_id: invoice.id,
          add_on_id: add_on_second.id,
          description: add_on_second.description,
          unit_amount_cents: 400,
          precise_unit_amount: 4,
          units: 1,
          amount_cents: 400,
          precise_amount_cents: 400.0,
          amount_currency: 'EUR',
          fee_type: 'add_on',
          payment_status: 'pending'
        )
        expect(second_fee.taxes.map(&:code)).to contain_exactly(tax.code)
      end
    end

    context 'when add_on_code is invalid' do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: 'desc-123'
          },
          {
            add_on_code: 'invalid'
          }
        ]
      end

      it 'does not create an invalid fee' do
        one_off_service.create

        expect(Fee.find_by(description: add_on_second.description)).to be_nil
      end
    end

    context 'when units is passed as string' do
      let(:fees) do
        [
          {
            add_on_code: add_on_first.code,
            unit_amount_cents: 1200,
            units: 2,
            description: 'desc-123',
            tax_codes: [tax2.code]
          }
        ]
      end

      it 'creates fees' do
        result = one_off_service.create

        expect(result).to be_success

        first_fee = result.fees[0]

        aggregate_failures do
          expect(first_fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            add_on_id: add_on_first.id,
            description: 'desc-123',
            unit_amount_cents: 1200,
            precise_unit_amount: 12,
            units: 2,
            amount_cents: 2400,
            precise_amount_cents: 2400.0,
            amount_currency: 'EUR',
            fee_type: 'add_on',
            payment_status: 'pending'
          )
          expect(first_fee.taxes.map(&:code)).to contain_exactly(tax2.code)
        end
      end
    end

    context 'when there is tax provider integration' do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { 'https://api.nango.dev/v1/anrok/finalized_invoices' }
      let(:body) do
        p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response_multiple_fees.json')
        json = File.read(p)

        # setting item_id based on the test example
        response = JSON.parse(json)
        response['succeededInvoices'].first['fees'].first['item_id'] = add_on_first.id
        response['succeededInvoices'].first['fees'].last['item_id'] = add_on_second.id

        response.to_json
      end
      let(:integration_collection_mapping) do
        create(
          :netsuite_collection_mapping,
          integration:,
          mapping_type: :fallback_item,
          settings: {external_id: '1', external_account_code: '11', external_name: ''}
        )
      end

      before do
        integration_collection_mapping
        integration_customer

        allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
        allow(lago_client).to receive(:post_with_response).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      it 'creates fees' do
        result = one_off_service.create

        first_fee = result.fees[0]
        second_fee = result.fees[1]

        aggregate_failures do
          expect(result).to be_success

          expect(first_fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            add_on_id: add_on_first.id,
            description: 'desc-123',
            unit_amount_cents: 1200,
            precise_unit_amount: 12,
            units: 2,
            amount_cents: 2400,
            amount_currency: 'EUR',
            fee_type: 'add_on',
            payment_status: 'pending',
            taxes_rate: 10
          )
          expect(first_fee.applied_taxes.first.amount_cents).to eq(240)
          expect(first_fee.applied_taxes.first.precise_amount_cents).to eq(240.0)

          expect(second_fee).to have_attributes(
            id: String,
            invoice_id: invoice.id,
            add_on_id: add_on_second.id,
            description: add_on_second.description,
            unit_amount_cents: 400,
            precise_unit_amount: 4,
            units: 1,
            amount_cents: 400,
            precise_amount_cents: 400.0,
            amount_currency: 'EUR',
            fee_type: 'add_on',
            payment_status: 'pending',
            taxes_rate: 15
          )
          expect(second_fee.applied_taxes.first.amount_cents).to eq(60)
          expect(second_fee.applied_taxes.first.precise_amount_cents).to eq(60.0)

          expect(invoice.reload.error_details.count).to eq(0)
        end
      end

      context 'when there is error received from the provider' do
        let(:body) do
          p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
          File.read(p)
        end

        it 'returns tax error' do
          result = one_off_service.create

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error.code).to eq('tax_error')
            expect(result.error.error_message).to eq('taxDateTooFarInFuture')

            expect(invoice.reload.error_details.count).to eq(1)
            expect(invoice.reload.error_details.first.details['tax_error']).to eq('taxDateTooFarInFuture')
          end
        end
      end
    end
  end
end
