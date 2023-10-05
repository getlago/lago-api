# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CustomerUsageService, type: :service do
  subject(:usage_service) do
    described_class.new(membership.user, customer_id:, subscription_id:)
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:customer) { create(:customer, organization:) }
  let(:customer_id) { customer&.id }
  let(:subscription_id) { subscription&.id }
  let(:plan) { create(:plan, interval: 'monthly') }
  let(:timestamp) { Time.current }

  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      started_at: Time.zone.now - 2.years,
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
      properties: { amount: '12.66' },
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
      timestamp:,
    )
  end

  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
  let(:cache) { Rails.cache }

  describe '#usage' do
    before do
      events if subscription
      charge
      allow(Rails).to receive(:cache).and_return(memory_store)
      Rails.cache.clear

      tax
    end

    it 'uses the Rails cache' do
      key = [
        'charge-usage',
        charge.id,
        subscription.id,
        charge.updated_at.iso8601,
      ].join('/')

      expect do
        usage_service.usage
      end.to change { cache.exist?(key) }.from(false).to(true)
    end

    it 'initializes an invoice' do
      result = usage_service.usage

      aggregate_failures do
        expect(result).to be_success

        expect(result.usage.id).to be_nil
        expect(result.usage.from_datetime).to eq(Time.current.beginning_of_month.iso8601)
        expect(result.usage.to_datetime).to eq(Time.current.end_of_month.iso8601)
        expect(result.usage.issuing_date).to eq(Time.zone.today.end_of_month.iso8601)
        expect(result.usage.fees.size).to eq(1)
        expect(result.usage.fees.first.charge.invoice_display_name).to eq(charge.invoice_display_name)

        expect(result.usage.currency).to eq('EUR')
        expect(result.usage.amount_cents).to eq(2532) # 1266 * 2
        expect(result.usage.taxes_amount_cents).to eq(506) # 1266 * 2 * 0.2 = 506.4
        expect(result.usage.total_amount_cents).to eq(3038)
      end
    end

    context 'with subscription started in current billing period' do
      before { subscription.update!(started_at: Time.zone.today) }

      it 'changes the from date of the invoice' do
        result = usage_service.usage

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
          billing_time: :anniversary,
        )
      end

      it 'initializes an invoice' do
        travel_to(current_date) do
          result = usage_service.usage

          aggregate_failures do
            expect(result).to be_success

            expect(result.usage.id).to be_nil
            expect(result.usage.from_datetime.to_date.to_s).to eq('2022-06-07')
            expect(result.usage.to_datetime.to_date.to_s).to eq('2022-07-06')
            expect(result.usage.issuing_date).to eq('2022-07-06')
            expect(result.usage.fees.size).to eq(1)

            expect(result.usage.currency).to eq('EUR')
            expect(result.usage.amount_cents).to eq(2532) # 1266 * 2
            expect(result.usage.taxes_amount_cents).to eq(506) # 1266 * 2 * 0.2 = 506.4
            expect(result.usage.total_amount_cents).to eq(3038)
          end
        end
      end
    end

    context 'when customer is not found' do
      let(:customer_id) { 'foo' }

      it 'returns an error' do
        result = usage_service.usage

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('customer_not_found')
      end
    end

    context 'when no_active_subscription' do
      let(:subscription) { nil }

      it 'fails' do
        result = usage_service.usage

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq('no_active_subscription')
        end
      end
    end
  end
end
