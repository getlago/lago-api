# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(charge:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:subscription) { create(:subscription) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

  let(:filters) { create_list(:billable_metric_filter, 2, billable_metric:) }
  let(:charge_filter) { create(:charge_filter, charge:) }
  let(:filter_value) do
    create(:charge_filter_value, charge_filter:, billable_metric_filter: filters.first)
  end

  before do
    charge
    filter_value
  end

  describe '#call' do
    it 'soft deletes the charge' do
      freeze_time do
        expect { destroy_service.call }.to change(Charge, :count).by(-1)
          .and change { charge.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it 'soft deletes all related filters' do
      freeze_time do
        expect { destroy_service.call }.to change { charge_filter.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it 'soft deletes all related filter values' do
      freeze_time do
        expect { destroy_service.call }.to change { filter_value.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    context 'when charge is not found' do
      it 'returns an error' do
        result = described_class.new(charge: nil).call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('charge_not_found')
      end
    end
  end
end
