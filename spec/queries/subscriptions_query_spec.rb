# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionsQuery, type: :query do
  subject(:subscriptions_query) { described_class.new(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

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
      let(:pagination) { {page: 2, limit: 10} }

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
      let(:filters) { {external_customer_id: customer.external_id} }

      it 'applies the filter' do
        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
        end
      end
    end

    context 'with plan filter' do
      let(:filters) { {plan_code: plan.code} }

      it 'applies the filter' do
        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
        end
      end
    end

    context 'with multiple status filter' do
      let(:filters) { {status: [:active, :pending]} }

      it 'returns correct subscriptions' do
        create(:subscription, :pending, customer:, plan:)
        create(:subscription, customer:, plan:, status: :canceled)
        create(:subscription, customer:, plan:, status: :terminated)
        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(2)
          expect(result.subscriptions.active.count).to eq(1)
          expect(result.subscriptions.pending.count).to eq(1)
          expect(result.subscriptions.canceled.count).to eq(0)
          expect(result.subscriptions.terminated.count).to eq(0)
        end
      end
    end

    context 'with pending status filter' do
      let(:filters) { {status: [:pending]} }

      it 'returns only pending subscriptions' do
        create(:subscription, :pending, customer:, plan:)
        create(:subscription, customer:, plan:, status: :canceled)
        create(:subscription, customer:, plan:, status: :terminated)

        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
          expect(result.subscriptions.active.count).to eq(0)
          expect(result.subscriptions.pending.count).to eq(1)
          expect(result.subscriptions.canceled.count).to eq(0)
          expect(result.subscriptions.terminated.count).to eq(0)
        end
      end
    end

    context 'with canceled status filter' do
      let(:filters) { {status: [:canceled]} }

      it 'returns only pending subscriptions' do
        create(:subscription, :pending, customer:, plan:)
        create(:subscription, customer:, plan:, status: :canceled)
        create(:subscription, customer:, plan:, status: :terminated)

        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
          expect(result.subscriptions.active.count).to eq(0)
          expect(result.subscriptions.pending.count).to eq(0)
          expect(result.subscriptions.canceled.count).to eq(1)
          expect(result.subscriptions.terminated.count).to eq(0)
        end
      end
    end

    context 'with terminated status filter' do
      let(:filters) { {status: [:terminated]} }

      it 'returns only pending subscriptions' do
        create(:subscription, :pending, customer:, plan:)
        create(:subscription, customer:, plan:, status: :canceled)
        create(:subscription, customer:, plan:, status: :terminated)

        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
          expect(result.subscriptions.active.count).to eq(0)
          expect(result.subscriptions.pending.count).to eq(0)
          expect(result.subscriptions.canceled.count).to eq(0)
          expect(result.subscriptions.terminated.count).to eq(1)
        end
      end
    end

    context 'with no status filter' do
      it 'returns only active subscriptions' do
        create(:subscription, :pending, customer:, plan:)

        result = subscriptions_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
          expect(result.subscriptions.active.count).to eq(1)
          expect(result.subscriptions.pending.count).to eq(0)
          expect(result.subscriptions.canceled.count).to eq(0)
          expect(result.subscriptions.terminated.count).to eq(0)
        end
      end
    end
  end
end
