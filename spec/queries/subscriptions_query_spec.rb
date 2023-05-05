# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionsQuery, type: :query do
  subject(:subscriptions_query) { described_class.new(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { BaseQuery::Pagination.new }
  let(:filters) { BaseQuery::Filters.new(query_filters) }

  let(:query_filters) { {} }

  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  before { subscription }

  describe 'call' do
    it 'returns a list of subscriptions' do
      result = subscriptions_query.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(1)
        expect(result.subscriptions).to eq([subscription])
      end
    end

    context 'with pagination' do
      let(:pagination) { BaseQuery::Pagination.new(page: 2, limit: 10) }

      it 'applies the pagination' do
        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(0)
          expect(result.subscriptions.current_page).to eq(2)
        end
      end
    end

    context 'with customer filter' do
      let(:query_filters) { { external_customer_id: customer.external_id } }

      it 'applies the filter' do
        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
        end
      end
    end

    context 'with plan filter' do
      let(:query_filters) { { plan_code: plan.code } }

      it 'applies the filter' do
        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
        end
      end
    end
  end
end
