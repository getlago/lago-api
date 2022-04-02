# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionsService, type: :service do
  subject(:subscription_service) { described_class.new }

  let(:organization) { create(:organization) }

  describe '.create' do
    let(:plan) { create(:plan, organization: organization) }
    let(:customer) { create(:customer, organization: organization) }

    let(:params) do
      {
        customer_id: customer.customer_id,
        plan_code: plan.code,
      }
    end

    it 'creates a subscription' do
      result = subscription_service.create(
        organization: organization,
        params: params,
      )

      expect(result).to be_success

      subscription = result.subscription

      aggregate_failures do
        expect(subscription.customer_id).to eq(customer.id)
        expect(subscription.plan_id).to eq(plan.id)
        expect(subscription.started_at).to be_present
        expect(subscription).to be_active
      end
    end

    context 'when customer does not exists' do
      let(:params) do
        {
          customer_id: SecureRandom.uuid,
          plan_code: plan.code,
        }
      end

      it 'creates a customer' do
        result = subscription_service.create(
          organization: organization,
          params: params,
        )

        expect(result).to be_success

        subscription = result.subscription

        aggregate_failures do
          expect(subscription.customer.customer_id).to eq(params[:customer_id])
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at).to be_present
          expect(subscription).to be_active
        end
      end
    end

    context 'when customer id is missing' do
      let(:params) do
        {
          customer_id: nil,
          plan_code: plan.code,
        }
      end

      it 'fails' do
        result = subscription_service.create(
          organization: organization,
          params: params,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('unable to find customer')
      end
    end

    context 'when plan doest not exists' do
      let(:params) do
        {
          customer_id: customer.customer_id,
          plan_code: 'invalid_plan',
        }
      end

      it 'fails' do
        result = subscription_service.create(
          organization: organization,
          params: params,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('plan does not exists')
      end
    end

    context 'when subscription already exists' do
      let!(:subscription) do
        create(
          :subscription,
          customer: customer,
          plan: plan,
          status: :active,
          started_at: Time.zone.now,
        )
      end

      it 'returns existing subscription' do
        result = subscription_service.create(
          organization: organization,
          params: params,
        )

        expect(result).to be_success
        expect(result.subscription).to eq(subscription)
        expect(result.subscription.started_at.to_s).to eq(subscription.started_at.to_s)
      end
    end
  end
end
