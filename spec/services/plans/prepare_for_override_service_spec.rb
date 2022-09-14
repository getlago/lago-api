# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::PrepareForOverrideService, type: :service do
  subject(:prepare_service) { described_class.new(organization, plan.code) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization: organization) }
  let(:standard_charge) { create(:standard_charge) }

  let(:params) do
    {
      trial_period: 1,
      amount_cents: 200,
      amount_currency: 'EUR',
      charges: [
        {
          id: standard_charge.id,
          charge_model: 'standard',
          properties: {
            amount: '0.22',
          },
        }
      ]
    }
  end

  let(:expected_params_without_code) do
    {
      name: plan.name,
      description: plan.description,
      bill_charges_monthly: plan.bill_charges_monthly,
      interval: plan.interval,
      pay_in_advance: plan.pay_in_advance,
      overridden_plan_id: plan.id,
      organization_id: organization.id,
      trial_period: 1,
      amount_cents: 200,
      amount_currency: 'EUR',
      charges: [
        {
          billable_metric_id: standard_charge.billable_metric_id,
          charge_model: 'standard',
          properties: {
            amount: '0.22',
          },
        }
      ]
    }
  end

  describe '.call' do
    it 'returns prepared params' do
      result = prepare_service.call(plan_params: params)

      expect(result[:code]).to start_with plan.code

      result.delete(:code)

      expect(result).to eq(expected_params_without_code)
    end
  end
end
