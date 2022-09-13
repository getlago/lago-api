# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::UpdateService, type: :service do
  subject(:plans_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
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
          charge_model: 'standard',
          properties: {
            amount: '100',
          },
        },
        {
          billable_metric_id: billable_metrics.last.id,
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

  describe 'update' do
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
        expect(result.error.error_code).to eq('billable_metrics_not_found')
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

      it 'updates existing charge and creates an other one' do
        expect { plans_service.update(**update_args) }
          .to change(Charge, :count).by(1)
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
        expect { plans_service.update(**update_args) }
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
        create(:subscription, plan: plan)
      end

      it 'updates only name description and new charges' do
        result = plans_service.update(**update_args)

        updated_plan = result.plan
        aggregate_failures do
          expect(updated_plan.name).to eq('Updated plan name')
          expect(plan.charges.count).to eq(2)
        end
      end
    end
  end

  describe 'update_from_api' do
    it 'updates the plan' do
      result = plans_service.update_from_api(
        organization: organization,
        code: plan.code,
        params: update_args,
      )

      aggregate_failures do
        expect(result).to be_success

        plan_result = result.plan
        expect(plan_result.id).to eq(plan.id)
        expect(plan_result.name).to eq(update_args[:name])
        expect(plan_result.code).to eq(update_args[:code])
        expect(plan_result.charges.count).to eq(2)
      end
    end

    context 'with validation errors' do
      let(:plan_name) { nil }

      it 'returns an error' do
        result = plans_service.update_from_api(
          organization: organization,
          code: plan.code,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error_code).to eq('unprocessable_entity')
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metrics) { create_list(:billable_metric, 2) }

      it 'returns an error' do
        result = plans_service.update_from_api(
          organization: organization,
          code: plan.code,
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('plan_not_found')
      end
    end

    context 'when plan is not found' do
      it 'returns an error' do
        result = plans_service.update_from_api(
          organization: organization,
          code: 'fake_code12345',
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('plan_not_found')
      end
    end

    context 'when attached to a subscription' do
      before { create(:subscription, plan: plan) }

      it 'updates only name and description' do
        result = plans_service.update_from_api(
          organization: organization,
          code: plan.code,
          params: update_args,
        )

        plan_result = result.plan
        aggregate_failures do
          expect(plan_result.name).to eq(update_args[:name])
          expect(plan_result.description).to eq(update_args[:description])
          expect(plan_result.amount_cents).not_to eq(update_args[:amount_cents])
          expect(plan.charges.count).to eq(2)
        end
      end
    end

    context 'with existing charges' do
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

      before { existing_charge }

      it 'updates existing charge and creates an other one' do
        expect do
          plans_service.update_from_api(
            organization: organization,
            code: plan.code,
            params: update_args,
          )
        end.to change(Charge, :count).by(1)
      end
    end

    context 'with charge to delete' do
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
          charges: [],
        }
      end

      before { existing_charge }

      it 'destroys the unattached charge' do
        expect do
          plans_service.update_from_api(
            organization: organization,
            code: plan.code,
            params: update_args,
          )
        end.to change { plan.charges.count }.by(-1)
      end
    end
  end
end
