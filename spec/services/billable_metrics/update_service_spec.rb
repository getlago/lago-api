# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::UpdateService, type: :service do
  subject(:update_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'update' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }
    let(:update_args) do
      {
        id: billable_metric&.id,
        name: 'New Metric',
        code: 'new_metric',
        description: 'New metric description',
        aggregation_type: 'count_agg',
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
        }
      end

      it 'returns an error' do
        result = subject.update(**update_args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'when billable metric is not found' do
      let(:billable_metric) { nil }

      it 'returns an error' do
        result = subject.update(**update_args)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metric_not_found')
      end
    end
  end

  describe 'update_from_api' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }
    let(:name) { 'New Metric' }
    let(:update_args) do
      {
        name: name,
        code: 'new_metric',
        description: 'New metric description',
        aggregation_type: 'count_agg',
        field_name: 'amount_sum',
      }
    end

    it 'updates the billable metric' do
      result = subject.update_from_api(
        organization: organization,
        code: billable_metric.code,
        params: update_args,
      )

      aggregate_failures do
        expect(result).to be_success

        metric = result.billable_metric
        expect(metric.id).to eq(billable_metric.id)
        expect(metric.name).to eq(update_args[:name])
        expect(metric.code).to eq(update_args[:code])
        expect(metric.aggregation_type).to eq(update_args[:aggregation_type])
      end
    end

    context 'with validation errors' do
      let(:name) { nil }

      it 'returns an error' do
        result = subject.update_from_api(
          organization: organization,
          code: billable_metric.code,
          params: update_args,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'when billable metric is not found' do
      it 'returns an error' do
        result = subject.update_from_api(
          organization: organization,
          code: 'fake_code12345',
          params: update_args,
        )

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metric_not_found')
      end
    end
  end
end
