# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(metric:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:metric) { create(:billable_metric, organization:) }

  before { metric }

  describe '#call' do
    it 'destroys the billable metric' do
      expect { destroy_service.call }.to change(BillableMetric, :count).by(-1)
    end

    context 'when billable metric is not found' do
      let(:metric) { nil }

      it 'returns an error' do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metric_not_found')
      end
    end
  end
end
