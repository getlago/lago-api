# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Subscriptions::CreateWithOverride, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:standard_charge) { create(:standard_charge) }
  let(:plan) { create(:plan, organization: organization, charges: [standard_charge]) }
  let(:customer) { create(:customer, organization: organization) }
  let(:billable_metric) { create(:billable_metric, organization: organization) }
  let(:current_user) { membership.user }
  let(:current_organization) { organization }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateSubscriptionWithOverrideInput!) {
        createSubscriptionWithOverride(input: $input) {
          id,
          status,
          name,
          startedAt,
          billingTime,
          customer {
            id
          },
          plan {
            id
          }
        }
      }
    GQL
  end

  let(:execute_request) do
    execute_graphql(
      current_user: current_user,
      current_organization: current_organization,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          overriddenPlanId: plan.id,
          name: 'invoice display name',
          billingTime: 'anniversary',
          plan: {
            name: plan.name,
            code: plan.code,
            interval: plan.interval,
            payInAdvance: plan.pay_in_advance,
            amountCents: 259,
            amountCurrency: plan.amount_currency,
            charges: [
              {
                billableMetricId: billable_metric.id,
                amount: '100.00',
                chargeModel: 'standard',
              },
            ],
          },
        },
      },
    )
  end

  before { plan }

  it 'creates a subscription' do
    result = execute_request

    result_data = result['data']['createSubscriptionWithOverride']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['status'].to_sym).to eq(:active)
      expect(result_data['name']).to eq('invoice display name')
      expect(result_data['startedAt']).to be_present
      expect(result_data['customer']['id']).to eq(customer.id)
      expect(result_data['plan']['id']).not_to eq(plan.id)
      expect(result_data['billingTime']).to eq('anniversary')
    end
  end

  it 'creates a new plan' do
    expect { execute_request }.to change(Plan, :count).by(1)
  end

  context 'without current user' do
    let(:current_user) { nil }

    it 'returns an error' do
      result = execute_request

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    let(:current_organization) { nil }

    it 'returns an error' do
      result = execute_request

      expect_forbidden_error(result)
    end
  end
end
