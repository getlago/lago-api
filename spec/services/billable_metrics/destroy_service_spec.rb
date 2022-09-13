# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  describe 'destroy' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }

    it 'destroys the billable metric' do
      id = billable_metric.id

      expect { destroy_service.destroy(id) }
        .to change(BillableMetric, :count).by(-1)
    end

    context 'when billable metric is not found' do
      it 'returns an error' do
        result = destroy_service.destroy(nil)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metric_not_found')
      end
    end

    context 'when billable metric is attached to subscription' do
      let(:subscription) { create(:subscription) }

      before do
        create(:standard_charge, plan: subscription.plan, billable_metric: billable_metric)
      end

      it 'returns an error' do
        result = destroy_service.destroy(billable_metric.id)

        expect(result).not_to be_success
        expect(result.error_code).to eq('forbidden')
      end
    end
  end

  describe 'destroy_from_api' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }

    it 'destroys the billable metric' do
      code = billable_metric.code

      expect { destroy_service.destroy_from_api(organization: organization, code: code) }
        .to change(BillableMetric, :count).by(-1)
    end

    context 'when billable metric is not found' do
      it 'returns an error' do
        result = destroy_service.destroy_from_api(organization: organization, code: 'invalid12345')

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metric_not_found')
      end
    end

    context 'when billable metric is attached to subscription' do
      let(:subscription) { create(:subscription) }

      before { create(:standard_charge, plan: subscription.plan, billable_metric: billable_metric) }

      it 'returns an error' do
        result = destroy_service.destroy_from_api(organization: organization, code: billable_metric.code)

        expect(result).not_to be_success
        expect(result.error_code).to eq('forbidden')
      end
    end
  end
end
