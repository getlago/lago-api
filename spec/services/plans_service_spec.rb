# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlansService, type: :service do
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
            amount_cents: 100,
            amount_currency: 'USD',
            charge_model: 'standard',
          },
          {
            billable_metric_id: billable_metrics.last.id,
            amount_cents: 300,
            amount_currency: 'EUR',
            vat_rate: 10.5,
            charge_model: 'standard',
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
            amount_cents: 100,
            amount_currency: 'USD',
            charge_model: 'standard',
          },
          {
            billable_metric_id: billable_metrics.last.id,
            amount_cents: 300,
            amount_currency: 'EUR',
            vat_rate: 10.5,
            charge_model: 'standard',
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
          :charge,
          plan_id: plan.id,
          billable_metric_id: billable_metrics.first.id,
          amount_cents: 300,
          amount_currency: 'USD',
          charge_model: 'standard',
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
              amount_cents: 100,
              amount_currency: 'USD',
              charge_model: 'standard',
            },
            {
              billable_metric_id: billable_metrics.last.id,
              amount_cents: 300,
              amount_currency: 'EUR',
              vat_rate: 10.5,
              charge_model: 'standard',
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
          :charge,
          plan_id: plan.id,
          billable_metric_id: billable_metrics.first.id,
          amount_cents: 300,
          amount_currency: 'USD',
          charge_model: 'standard',
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

  describe 'destroy' do
    let(:plan) { create(:plan, organization: organization) }

    it 'destroys the plan' do
      id = plan.id

      expect { plans_service.destroy(id) }
        .to change(Plan, :count).by(-1)
    end

    context 'when plan is not found' do
      it 'returns an error' do
        result = plans_service.destroy(nil)

        expect(result).not_to be_success
        expect(result.error).to eq('not_found')
      end
    end

    context 'when plan is attached to subscription' do
      before do
        create(:subscription, plan: plan)
      end

      it 'returns an error' do
        result = plans_service.destroy(plan.id)

        expect(result).not_to be_success
        expect(result.error_code).to eq('forbidden')
      end
    end
  end
end
