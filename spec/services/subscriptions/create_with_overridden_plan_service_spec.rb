# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::CreateWithOverriddenPlanService, type: :service do
  subject(:override_service) { described_class.new }

  let(:organization) { create(:organization) }

  describe '.call' do
    let(:plan) { create(:plan, amount_cents: 100, organization: organization) }
    let(:customer) { create(:customer, organization: organization) }
    let(:billable_metric) { create(:billable_metric, organization: organization) }
    let(:plan_name) { plan.name }
    let(:customer_id) { customer.id }
    let(:billing_time) { :anniversary }

    let(:plan_params) do
      {
        name: plan_name,
        code: "#{plan.code}-123456",
        interval: plan.interval,
        overridden_plan_id: plan.id,
        pay_in_advance: plan.pay_in_advance,
        organization_id: organization.id,
        amount_cents: 299,
        amount_currency: plan.amount_currency,
        charges: [
          {
            billable_metric_id: billable_metric.id,
            charge_model: 'standard',
            properties: {
              amount: '100',
            },
          },
        ],
      }
    end

    let(:subscription_params) do
      {
        customer_id: customer_id,
        name: 'subscription display name',
        organization_id: organization.id,
        billing_time: billing_time,
      }
    end

    before { plan }

    it 'creates a subscription' do
      result = override_service.call(plan_args: plan_params, subscription_args: subscription_params)

      expect(result).to be_success

      subscription = result.subscription

      aggregate_failures do
        expect(subscription.customer_id).to eq(customer.id)
        expect(subscription.plan_id).not_to eq(plan.id)
        expect(subscription.started_at).to be_present
        expect(subscription.subscription_date).to be_present
        expect(subscription).to be_active
        expect(subscription).to be_anniversary
      end
    end

    it 'creates a new plan' do
      expect do
        override_service.call(plan_args: plan_params, subscription_args: subscription_params)
      end.to change(Plan, :count).by(1)
    end

    it 'creates a new plan that is correctly linked to overridden_plan' do
      result = override_service.call(plan_args: plan_params, subscription_args: subscription_params)

      expect(result.subscription.plan.overridden_plan_id).to eq(plan.id)
    end

    context 'when plan is invalid' do
      let(:plan_name) { nil }

      it 'fails' do
        result = override_service.call(plan_args: plan_params, subscription_args: subscription_params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'when customer does not exists' do
      let(:customer_id) { "#{customer.id}-invalid" }

      it 'fails' do
        result = override_service.call(plan_args: plan_params, subscription_args: subscription_params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error_code).to eq('missing_argument')
          expect(result.error).to eq('unable to find customer')
        end
      end
    end

    context 'when billing_time is invalid' do
      let(:billing_time) { :foo }

      it 'fails' do
        result = override_service.call(plan_args: plan_params, subscription_args: subscription_params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to eq('Validation error on the record')
          expect(result.error_code).to eq('unprocessable_entity')
          expect(result.error_details.keys).to eq([:billing_time])
        end
      end
    end
  end
end
