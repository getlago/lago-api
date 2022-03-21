# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetricsService, type: :service do
  subject { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    let(:create_args) do
      {
        name: 'New Metric',
        code: 'new_metric',
        description: 'New metric description',
        organization_id: organization.id,
        aggregation_type: 'count_agg',
        billable_period: 'recurring',
        properties: {}
      }
    end

    it 'creates a billable metric' do
      expect { subject.create(**create_args) }
        .to change { BillableMetric.count }.by(1)
    end

    context 'with validation error' do
      before do
        create(
          :billable_metric,
          code: create_args[:code],
          organization: membership.organization
        )
      end

      it 'returns an error' do
        expect { subject.create(**create_args) }
          .to raise_error(ActiveRecord::RecordInvalid)
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
    let(:billable_metric) { create(:billable_metric, organization: organization) }
    let(:update_args) do
      {
        id: billable_metric&.id,
        name: 'New Metric',
        code: 'new_metric',
        description: 'New metric description',
        aggregation_type: 'count_agg',
        billable_period: 'recurring',
        properties: {}
      }
    end

    it 'updates the billable metric' do
      result = subject.update(**update_args)

      aggregate_failures do
        expect(result).to be_success

        metric = result.billable_metric
        expect(metric.id).to eq(billable_metric.id)
        expect(metric.name).to eq('New Metric')
        expect(metric.code).to eq('new_metric')
        expect(metric.aggregation_type).to eq('count_agg')
        expect(metric.billable_period).to eq('recurring')
      end
    end

    context 'with validation errors' do
      let(:update_args) do
        {
          id: billable_metric.id,
          name: nil,
          code: 'new_metric',
          description: 'New metric description',
          aggregation_type: 'count_agg',
          billable_period: 'recurring',
          properties: {}
        }
      end

      it 'returns an error' do
        expect { subject.update(**update_args) }
          .to raise_error(ActiveRecord::RecordInvalid)
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

    context 'when billable metric is not found' do
      let(:billable_metric) { nil }

      it 'returns an error' do
        result = subject.update(**update_args)

        expect(result).to_not be_success
        expect(result.error).to eq('not_found')
      end
    end
  end

  describe 'destroy' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }

    it 'destroys the billable metric' do
      id = billable_metric.id

      expect { subject.destroy(id) }
        .to change(BillableMetric, :count).by(-1)
    end

    context 'when user is not member of the organization' do
      let(:organization) { create(:organization) }

      it 'returns an error' do
        result = subject.destroy(billable_metric.id)

        expect(result.success?).to be_falsey
        expect(result.error).to eq('not_organization_member')
      end
    end

    context 'when billable metric is not found' do
      it 'returns an error' do
        result = subject.destroy(nil)

        expect(result).to_not be_success
        expect(result.error).to eq('not_found')
      end
    end
  end
end
