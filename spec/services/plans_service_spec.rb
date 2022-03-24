# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlansService, type: :service do
  subject { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:plan_name) { 'Some plan name' }
    let(:billable_metrics) do
      create_list(:billable_metric, 3, organization: organization)
    end

    let(:create_args) do
      {
        name: plan_name,
        organization_id: organization.id,
        billable_metric_ids: billable_metrics.map(&:id)
      }
    end

    it 'creates a plan' do
      expect { subject.create(**create_args) }
        .to change { Plan.count }.by(1)

        plan = Plan.order(:created_at).last

      expect(plan.billable_metrics.count).to eq(3)
    end

    context 'with validation error' do
      let(:plan_name) { nil }

      it 'returns an error' do
        expect { subject.create(**create_args) }
          .to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metrics) { [create(:billable_metric)] }

      it 'returns an error' do
        result = subject.create(**create_args)

        expect(result).to_not be_success
        expect(result.error).to eq('Billable metrics does not exists')
      end
    end

    context 'when user is not member of the organization' do
      let(:organization) { create(:organization) }

      it 'returns an error' do
        result = subject.create(**create_args)

        expect(result.success?).to be_falsey
        expect(result.error).to eq('not_organization_member')
      end
    end
  end

  describe 'update' do
    let(:plan) { create(:plan, organization: organization) }
    let(:plan_name) { 'Updated plan name' }
    let(:billable_metrics) do
      create_list(:billable_metric, 4, organization: organization)
    end

    let(:update_args) do
      {
        id: plan.id,
        name: plan_name,
        organization_id: organization.id,
        billable_metric_ids: billable_metrics.map(&:id)
      }
    end

    it 'updates a plan' do
      result = subject.update(**update_args)

      updated_plan = result.plan
      aggregate_failures do
        expect(updated_plan.name).to eq('Updated plan name')
        expect(plan.billable_metrics.count).to eq(4)
      end
    end

    context 'with validation error' do
      let(:plan_name) { nil }

      it 'returns an error' do
        expect { subject.update(**update_args) }
          .to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'with metrics from other organization' do
      let(:billable_metrics) { [create(:billable_metric)] }

      it 'returns an error' do
        result = subject.update(**update_args)

        expect(result).to_not be_success
        expect(result.error).to eq('Billable metrics does not exists')
      end
    end

    context 'when user is not member of the organization' do
      let(:organization) { create(:organization) }

      it 'returns an error' do
        result = subject.update(**update_args)

        expect(result.success?).to be_falsey
        expect(result.error).to eq('not_organization_member')
      end
    end
  end

  describe 'destroy' do
    let(:plan) { create(:plan, organization: organization) }

    it 'destroys the plan' do
      id = plan.id

      expect { subject.destroy(id) }
        .to change(Plan, :count).by(-1)
    end

    context 'when user is not member of the organization' do
      let(:organization) { create(:organization) }

      it 'returns an error' do
        result = subject.destroy(plan.id)

        expect(result.success?).to be_falsey
        expect(result.error).to eq('not_organization_member')
      end
    end

    context 'when plan is not found' do
      it 'returns an error' do
        result = subject.destroy(nil)

        expect(result).to_not be_success
        expect(result.error).to eq('not_found')
      end
    end
  end
end
