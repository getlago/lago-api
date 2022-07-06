# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::CreateService, type: :service do
  subject(:plans_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:plan_name) { 'Some plan name' }
    let(:billable_metrics) { create_list(:billable_metric, 2, organization: organization) }

    let(:create_args) do
      {
        name: plan_name,
        organization_id: organization.id,
        code: 'new_plan',
        interval: 'monthly',
        pay_in_advance: false,
        amount_cents: 200,
        amount_currency: 'EUR',
        charges: [
          {
            billable_metric_id: billable_metrics.first.id,
            amount_currency: 'USD',
            charge_model: 'standard',
            properties: {
              amount: '100',
            },
          },
          {
            billable_metric_id: billable_metrics.last.id,
            amount_currency: 'EUR',
            charge_model: 'graduated',
            properties: [
              {
                from_value: 0,
                to_value: 10,
                per_unit_amount: '2',
                flat_amount: '0',
              },
              {
                from_value: 11,
                to_value: nil,
                per_unit_amount: '3',
                flat_amount: '3',
              },
            ],
          },
        ],
      }
    end

    it 'creates a plan' do
      expect { plans_service.create(**create_args) }
        .to change(Plan, :count).by(1)

      plan = Plan.order(:created_at).last

      expect(plan.charges.count).to eq(2)
    end

    context 'with validation error' do
      let(:plan_name) { nil }

      it 'returns an error' do
        result = plans_service.create(**create_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metrics) { create_list(:billable_metric, 2) }

      it 'returns an error' do
        result = plans_service.create(**create_args)

        expect(result).not_to be_success
        expect(result.error).to eq('Billable metrics does not exists')
      end
    end
  end
end
