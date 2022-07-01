# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::UpdateService, type: :service do
  subject(:plans_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'update' do
    let(:plan) { create(:plan, organization: organization) }
    let(:plan_name) { 'Updated plan name' }
    let(:billable_metrics) do
      create_list(:billable_metric, 2, organization: organization)
    end

    let(:update_args) do
      {
        id: plan.id,
        name: plan_name,
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

    it 'updates a plan' do
      result = plans_service.update(**update_args)

      updated_plan = result.plan
      aggregate_failures do
        expect(updated_plan.name).to eq('Updated plan name')
        expect(plan.charges.count).to eq(2)
      end
    end

    context 'with validation error' do
      let(:plan_name) { nil }

      it 'returns an error' do
        result = plans_service.update(**update_args)

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metrics) { create_list(:billable_metric, 2) }

      it 'returns an error' do
        result = plans_service.update(**update_args)

        expect(result).not_to be_success
        expect(result.error).to eq('Billable metrics does not exists')
      end
    end

    context 'with existing charges' do
      let!(:existing_charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: billable_metrics.first.id,
          properties: {
            amount: '300',
            amount_currency: 'USD',
          },
        )
      end

      let(:update_args) do
        {
          id: plan.id,
          name: plan_name,
          code: 'new_plan',
          interval: 'monthly',
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: 'EUR',
          charges: [
            {
              id: existing_charge.id,
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
              charge_model: 'standard',
              properties: {
                amount: '300',
              }
            },
          ],
        }
      end

      it 'updates existing charge and creates an other one' do
        expect { plans_service.update(**update_args) }
          .to change(Charge, :count).by(1)
      end
    end

    context 'with charge to delete' do
      let!(:charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: billable_metrics.first.id,
          amount_currency: 'USD',
          properties: {
            amount: '300',
          },
        )
      end

      let(:update_args) do
        {
          id: plan.id,
          name: plan_name,
          code: 'new_plan',
          interval: 'monthly',
          pay_in_advance: false,
          amount_cents: 200,
          amount_currency: 'EUR',
          charges: [],
        }
      end

      it 'destroys the unattached charge' do
        expect { plans_service.update(**update_args) }
          .to change { plan.charges.count }.by(-1)
      end
    end

    context 'when attached to a subscription' do
      before do
        create(:subscription, plan: plan)
      end

      it 'updates only name and description' do
        result = plans_service.update(**update_args)

        updated_plan = result.plan
        aggregate_failures do
          expect(updated_plan.name).to eq('Updated plan name')
          expect(plan.charges.count).to eq(0)
        end
      end
    end
  end
end
