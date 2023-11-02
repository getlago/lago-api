# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PastUsageQuery, type: :query do
  subject(:usage_query) { described_class.new(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { BaseQuery::Pagination.new }
  let(:filters) { BaseQuery::Filters.new(query_filters) }

  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:query_filters) do
    {
      external_customer_id: customer.external_id,
      external_subscription_id: subscription.external_id,
    }
  end

  let(:invoice_subscription1) do
    create(
      :invoice_subscription,
      charges_from_datetime: DateTime.parse('2023-08-17T00:00:00'),
      charges_to_datetime: DateTime.parse('2023-09-16T23:59:59'),
      subscription:,
    )
  end

  let(:invoice_subscription2) do
    create(
      :invoice_subscription,
      charges_from_datetime: DateTime.parse('2023-07-17T00:00:00'),
      charges_to_datetime: DateTime.parse('2023-08-16T23:59:59'),
      subscription:,
    )
  end

  before do
    invoice_subscription1
    invoice_subscription2
  end

  describe 'call' do
    it 'returns a list of invoice_subscription' do
      result = usage_query.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.usage_periods.count).to eq(2)
      end
    end

    context 'when external_customer_id is missing' do
      let(:query_filters) { { external_subscription_id: subscription.external_id } }

      it 'returns a validation failure' do
        result = usage_query.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:external_customer_id)
          expect(result.error.messages[:external_customer_id]).to include('value_is_mandatory')
        end
      end
    end

    context 'when external_subscription_id is missing' do
      let(:query_filters) { { external_customer_id: customer.external_id } }

      it 'returns a validation failure' do
        result = usage_query.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:external_subscription_id)
          expect(result.error.messages[:external_subscription_id]).to include('value_is_mandatory')
        end
      end
    end

    context 'with billable_metric_code' do
      let(:billable_metric1) { create(:billable_metric, organization:) }
      let(:billable_metric_code) { billable_metric1&.code }

      let(:billable_metric2) { create(:billable_metric, organization:) }

      let(:charge1) { create(:standard_charge, plan:, billable_metric: billable_metric1) }
      let(:charge2) { create(:standard_charge, plan:, billable_metric: billable_metric2) }

      let(:fee1) { create(:charge_fee, charge: charge1, invoice: invoice_subscription1.invoice) }
      let(:fee2) { create(:charge_fee, charge: charge2, invoice: invoice_subscription1.invoice) }

      let(:query_filters) do
        {
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          billable_metric_code:,
        }
      end

      before do
        fee1
        fee2
      end

      it 'filters the fees accordingly' do
        result = usage_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.usage_periods.count).to eq(2)
          expect(result.usage_periods.first.fees.count).to eq(1)
        end
      end

      context 'when billable metric is not found' do
        let(:billable_metric_code) { 'unknown_code' }

        it 'returns a not found failure' do
          result = usage_query.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.error_code).to eq('billable_metric_not_found')
          end
        end
      end
    end

    context 'with periods_count filter' do
      let(:periods_count) { 1 }
      let(:query_filters) do
        {
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          periods_count:,
        }
      end

      it 'returns last requested periods' do
        result = usage_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.usage_periods.count).to eq(1)
          expect(result.usage_periods.first.invoice_subscription).to eq(invoice_subscription1)
        end
      end

      context 'when periods_count is higher than billed period count' do
        let(:periods_count) { 10 }

        it 'returns all periods' do
          result = usage_query.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.usage_periods.count).to eq(2)
          end
        end
      end
    end
  end
end
