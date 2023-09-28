# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PastUsageQuery, type: :query do
  subject(:usage_query) { described_class.new(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { BaseQuery::Pagination.new }
  let(:filters) { BaseQuery::Filters.new(query_filters) }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  let(:query_filters) do
    {
      external_customer_id: customer.external_id,
      external_subscription_id: subscription.external_id,
    }
  end

  let(:invoice_subscription1) do
    create(
      :invoice_subscription,
      from_datetime: DateTime.parse('2023-08-17T00:00:00'),
      to_datetime: DateTime.parse('2023-09-16T23:59:59'),
      subscription:,
    )
  end

  let(:invoice_subscription2) do
    create(
      :invoice_subscription,
      from_datetime: DateTime.parse('2023-07-17T00:00:00'),
      to_datetime: DateTime.parse('2023-08-16T23:59:59'),
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
        expect(result.usage.count).to eq(2)
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
  end
end
