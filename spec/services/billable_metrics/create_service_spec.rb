# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::CreateService, type: :service do
  subject(:create_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'create' do
    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    let(:create_args) do
      {
        name: 'New Metric',
        code: 'new_metric',
        description: 'New metric description',
        organization_id: organization.id,
        aggregation_type: 'count_agg',
        recurring: false
      }
    end

    it 'creates a billable metric' do
      expect { create_service.create(**create_args) }
        .to change(BillableMetric, :count).by(1)
    end

    context 'with code already used by a deleted metric' do
      it 'creates a billable metric with the same code' do
        create(:billable_metric, organization:, code: 'new_metric', deleted_at: Time.current)

        expect { create_service.create(**create_args) }
          .to change(BillableMetric, :count).by(1)

        metrics = organization.billable_metrics.with_discarded
        expect(metrics.count).to eq(2)
        expect(metrics.pluck(:code).uniq).to eq(['new_metric'])
      end
    end

    context 'with filters arguments' do
      let(:filters) do
        [
          {
            key: 'cloud',
            values: %w[aws google]
          }
        ]
      end

      it 'creates billable metric\'s filters' do
        expect { create_service.create(**create_args.merge(filters:)) }
          .to change(BillableMetricFilter, :count).by(1)
      end

      it 'returns an error if a filter is invalid' do
        result = create_service.create(**create_args.merge(filters: [{key: 'foo'}]))

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:values]).to eq(['value_is_mandatory'])
        end
      end
    end

    it 'calls SegmentTrackJob' do
      metric = create_service.create(**create_args).billable_metric

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'billable_metric_created',
        properties: {
          code: metric.code,
          name: metric.name,
          description: metric.description,
          aggregation_type: metric.aggregation_type,
          aggregation_property: metric.field_name,
          organization_id: metric.organization_id
        }
      )
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
        result = create_service.create(**create_args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:code]).to eq(['value_already_exist'])
        end
      end
    end

    context 'with custom aggregation' do
      let(:create_args) do
        {
          name: 'New Metric',
          code: 'new_metric',
          description: 'New metric description',
          organization_id: organization.id,
          aggregation_type: 'custom_agg',
          recurring: false
        }
      end

      it 'returns a forbidden failure' do
        result = create_service.create(**create_args)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end
  end
end
