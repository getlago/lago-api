# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::CreateService, type: :service do
  subject(:plans_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:plan_name) { 'Some plan name' }
    let(:billable_metrics) { create_list(:billable_metric, 2, organization: organization) }
    let(:group) { create(:group, billable_metric: billable_metrics.first) }
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
            instant: true,
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

    around { |test| lago_premium!(&test) }

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a plan' do
      expect { plans_service.create(**create_args) }
        .to change(Plan, :count).by(1)
    end

    it 'creates charges' do
      plans_service.create(**create_args)

      plan = Plan.order(:created_at).last
      expect(plan.charges.count).to eq(2)

      standard_charge = plan.charges.standard.first
      graduated_charge = plan.charges.graduated.first

      expect(standard_charge).not_to be_instant
      expect(standard_charge.group_properties.first).to have_attributes(
        {
          group_id: group.id,
          values: { 'amount' => '100' },
        },
      )

      expect(graduated_charge).to be_instant
    end

    it 'calls SegmentTrackJob' do
      plan = plans_service.create(**create_args).plan

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'plan_created',
        properties: {
          code: plan.code,
          name: plan.name,
          description: plan.description,
          plan_interval: plan.interval,
          plan_amount_cents: plan.amount_cents,
          plan_period: 'arrears',
          trial: plan.trial_period,
          nb_charges: 2,
          nb_standard_charges: 1,
          nb_percentage_charges: 0,
          nb_graduated_charges: 1,
          nb_package_charges: 0,
          organization_id: plan.organization_id,
        },
      )
    end

    context 'with code already used by a deleted plan' do
      it 'creates a plan with the same code' do
        create(:plan, organization:, code: 'new_plan', deleted_at: Time.current)

        expect { plans_service.create(**create_args) }.to change(Plan, :count).by(1)

        plans = organization.plans.with_discarded
        expect(plans.count).to eq(2)
        expect(plans.pluck(:code).uniq).to eq(['new_plan'])
      end
    end

    context 'with validation error' do
      let(:plan_name) { nil }

      it 'returns an error' do
        result = plans_service.create(**create_args)

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
        result = plans_service.create(**create_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metrics_not_found')
      end
    end
  end
end
