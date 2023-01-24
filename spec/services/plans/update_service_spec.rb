# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::UpdateService, type: :service do
  subject(:plans_service) { described_class.new(plan:, params: update_args) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:plan_name) { 'Updated plan name' }
  let(:group) { create(:group, billable_metric: billable_metrics.first) }

  let(:billable_metrics) do
    create_list(:billable_metric, 2, organization:)
  end

  let(:update_args) do
    {
      name: plan_name,
      code: 'new_plan',
      interval: 'monthly',
      pay_in_advance: false,
      amount_cents: 200,
      amount_currency: 'EUR',
      charges: [
        {
          billable_metric_id: billable_metrics.first.id,
          charge_model: 'standard',
          group_properties: [
            {
              group_id: group.id,
              values: { amount: '100' },
            },
          ],
        },
        {
          billable_metric_id: billable_metrics.last.id,
          charge_model: 'graduated',
          properties: {
            graduated_ranges: [
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
        },
      ],
    }
  end

  describe 'call' do
    it 'updates a plan' do
      result = plans_service.call

      updated_plan = result.plan
      aggregate_failures do
        expect(updated_plan.name).to eq('Updated plan name')
        expect(plan.charges.count).to eq(2)
      end
    end

    context 'when plan is not found' do
      let(:plan) { nil }

      it 'returns an error' do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('plan_not_found')
        end
      end
    end

    context 'with validation error' do
      let(:plan_name) { nil }

      it 'returns an error' do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metrics) { create_list(:billable_metric, 2) }

      it 'returns an error' do
        result = plans_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('billable_metrics_not_found')
        end
      end
    end

    context 'with existing charges' do
      let!(:existing_charge) do
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
          charges: [
            {
              id: existing_charge.id,
              billable_metric_id: billable_metrics.first.id,
              charge_model: 'standard',
              group_properties: [
                {
                  group_id: group.id,
                  values: { amount: '100' },
                },
              ],
            },
            {
              billable_metric_id: billable_metrics.last.id,
              charge_model: 'standard',
              properties: {
                amount: '300',
              },
            },
          ],
        }
      end

      it 'updates existing charge and creates an other one' do
        expect { plans_service.call }
          .to change(Charge, :count).by(1)
      end

      it 'updates group properties' do
        expect { plans_service.call }
          .to change(GroupProperty, :count).by(1)

        expect(existing_charge.reload.group_properties.first).to have_attributes(
          group_id: group.id,
          values: { 'amount' => '100' },
        )
      end
    end

    context 'with charge to delete' do
      let(:charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: billable_metrics.first.id,
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

      before { charge }

      it 'destroys the unattached charge' do
        expect { plans_service.call }
          .to change { plan.charges.count }.by(-1)
      end
    end

    context 'when attached to a subscription' do
      let(:existing_charge) do
        create(
          :standard_charge,
          plan_id: plan.id,
          billable_metric_id: billable_metrics.first.id,
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
          charges: [
            {
              id: existing_charge.id,
              billable_metric_id: billable_metrics.first.id,
              charge_model: 'standard',
              properties: {
                amount: '100',
              },
            },
            {
              billable_metric_id: billable_metrics.last.id,
              charge_model: 'standard',
              properties: {
                amount: '300',
              },
            },
          ],
        }
      end

      before do
        create(:subscription, plan:)
      end

      it 'updates only name description and new charges' do
        result = plans_service.call

        updated_plan = result.plan
        aggregate_failures do
          expect(updated_plan.name).to eq('Updated plan name')
          expect(plan.charges.count).to eq(2)
        end
      end
    end
  end
end
