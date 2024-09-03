# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CustomerUsageService, type: :service, cache: :memory do
  subject(:usage_service) do
    described_class.with_ids(membership.user, customer_id:, subscription_id:, apply_taxes:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:customer) { create(:customer, organization:) }
  let(:customer_id) { customer&.id }
  let(:subscription_id) { subscription&.id }
  let(:plan) { create(:plan, interval: 'monthly') }
  let(:timestamp) { Time.current }
  let(:apply_taxes) { true }

  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      started_at: Time.zone.now - 2.years
    )
  end

  let(:billable_metric) do
    create(:billable_metric, aggregation_type: 'count_agg')
  end

  let(:charge) do
    create(
      :standard_charge,
      plan:,
      billable_metric:,
      properties: {amount: '12.66'}
    )
  end

  let(:events) do
    create_list(
      :event,
      2,
      organization:,
      subscription:,
      customer:,
      code: billable_metric.code,
      timestamp:
    )
  end

  describe '#call' do
    before do
      events if subscription
      charge
      Rails.cache.clear

      tax
    end

    it 'uses the Rails cache' do
      key = [
        'charge-usage',
        charge.id,
        subscription.id,
        charge.updated_at.iso8601
      ].join('/')

      expect do
        usage_service.call
      end.to change { Rails.cache.exist?(key) }.from(false).to(true)
    end

    it 'initializes an invoice' do
      result = usage_service.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.invoice).to be_a(Invoice)

        expect(result.usage).to have_attributes(
          from_datetime: Time.current.beginning_of_month.iso8601,
          to_datetime: Time.current.end_of_month.iso8601,
          issuing_date: Time.zone.today.end_of_month.iso8601,
          currency: 'EUR',
          amount_cents: 2532, # 1266 * 2,
          taxes_amount_cents: 506, # 1266 * 2 * 0.2 = 506.4
          total_amount_cents: 3038
        )
        expect(result.usage.fees.size).to eq(1)
        expect(result.usage.fees.first.charge.invoice_display_name).to eq(charge.invoice_display_name)
      end
    end

    context 'when apply_taxes property is set to false' do
      let(:apply_taxes) { false }

      it 'initializes an invoice' do
        result = usage_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice).to be_a(Invoice)

          expect(result.usage).to have_attributes(
            from_datetime: Time.current.beginning_of_month.iso8601,
            to_datetime: Time.current.end_of_month.iso8601,
            issuing_date: Time.zone.today.end_of_month.iso8601,
            currency: 'EUR',
            amount_cents: 2532, # 1266 * 2,
            taxes_amount_cents: 0,
            total_amount_cents: 2532
          )
          expect(result.usage.fees.size).to eq(1)
          expect(result.usage.fees.first.charge.invoice_display_name).to eq(charge.invoice_display_name)
        end
      end
    end

    context 'when there is tax provider integration' do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { 'https://api.nango.dev/v1/anrok/draft_invoices' }
      let(:body) do
        p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response.json')
        json = File.read(p)

        # setting item_id based on the test example
        response = JSON.parse(json)
        response['succeededInvoices'].first['fees'].last['item_id'] = charge.billable_metric.id

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

      it 'initializes an invoice' do
        result = usage_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice).to be_a(Invoice)

          expect(result.usage).to have_attributes(
            from_datetime: Time.current.beginning_of_month.iso8601,
            to_datetime: Time.current.end_of_month.iso8601,
            issuing_date: Time.zone.today.end_of_month.iso8601,
            currency: 'EUR',
            amount_cents: 2532, # 1266 * 2,
            taxes_amount_cents: 253, # 2532 * 0.1
            total_amount_cents: 2785
          )
          expect(result.usage.fees.size).to eq(1)
          expect(result.usage.fees.first.charge.invoice_display_name).to eq(charge.invoice_display_name)
        end
      end

      it 'uses the Rails cache' do
        key = [
          'provider-taxes',
          subscription.id,
          plan.updated_at.iso8601
        ].join('/')

        expect do
          usage_service.call
        end.to change { Rails.cache.exist?(key) }.from(false).to(true)
      end

      context 'when there is error received from the provider' do
        let(:body) do
          p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
          File.read(p)
        end

        it 'returns tax error' do
          result = usage_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:tax_error]).to eq(['taxDateTooFarInFuture'])
          end
        end
      end
    end

    context 'with subscription started in current billing period' do
      before { subscription.update!(started_at: Time.zone.today) }

      it 'changes the from date of the invoice' do
        result = usage_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.usage.id).to be_nil
          expect(result.usage.from_datetime).to eq(subscription.started_at.iso8601)
        end
      end
    end

    context 'when subscription is billed on anniversary date' do
      let(:current_date) { DateTime.parse('2022-06-22') }
      let(:started_at) { DateTime.parse('2022-03-07') }
      let(:subscription_at) { started_at }
      let(:timestamp) { current_date }

      let(:subscription) do
        create(
          :subscription,
          plan:,
          customer:,
          subscription_at:,
          started_at:,
          billing_time: :anniversary
        )
      end

      it 'initializes an invoice' do
        travel_to(current_date) do
          result = usage_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice).to be_a(Invoice)

            expect(result.usage).to have_attributes(
              issuing_date: '2022-07-06',
              currency: 'EUR',
              amount_cents: 2532, # 1266 * 2,
              taxes_amount_cents: 506, # 1266 * 2 * 0.2 = 506.4
              total_amount_cents: 3038
            )

            expect(result.usage.from_datetime.to_date.to_s).to eq('2022-06-07')
            expect(result.usage.to_datetime.to_date.to_s).to eq('2022-07-06')
            expect(result.usage.fees.size).to eq(1)
          end
        end
      end
    end

    context 'when customer is not found' do
      let(:customer_id) { 'foo' }

      it 'returns an error' do
        result = usage_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('customer_not_found')
      end
    end

    context 'when no_active_subscription' do
      let(:subscription) { nil }

      it 'fails' do
        result = usage_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq('no_active_subscription')
        end
      end
    end
  end
end
