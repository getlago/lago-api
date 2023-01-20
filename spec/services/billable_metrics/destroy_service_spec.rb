# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'destroy' do
    let(:billable_metric) { create(:billable_metric, organization:) }

    before { billable_metric }

    it 'destroys the billable metric' do
      expect { destroy_service.destroy(metric: billable_metric) }
        .to change(BillableMetric, :count).by(-1)
    end

    context 'when billable metric is not found' do
      it 'returns an error' do
        result = destroy_service.destroy(metric: nil)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metric_not_found')
      end
    end

    context 'when billable metric is attached to subscription' do
      let(:subscription) { create(:subscription) }

      before do
        create(:standard_charge, plan: subscription.plan, billable_metric:)
      end

      it 'returns an error' do
        result = destroy_service.destroy(metric: billable_metric)

        expect(result).not_to be_success
        expect(result.error.code).to eq('attached_to_an_active_subscription')
      end
    end
  end
end
