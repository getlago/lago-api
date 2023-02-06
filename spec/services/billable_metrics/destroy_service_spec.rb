# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(metric: billable_metric) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:subscription) { create(:subscription) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
  let(:group) { create(:group, billable_metric:) }
  let(:group_property) { create(:group_property, group:, charge:) }

  before do
    charge
    group_property

    allow(SegmentTrackJob).to receive(:perform_later)
    allow(BillableMetrics::DeleteEventsJob).to receive(:perform_later).and_call_original
    allow(Invoices::RefreshDraftService).to receive(:call)
  end

  describe '#call' do
    it 'soft deletes the billable metric' do
      freeze_time do
        expect { destroy_service.call }.to change(BillableMetric, :count).by(-1)
          .and change { billable_metric.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it 'soft deletes all the related charges' do
      freeze_time do
        expect { destroy_service.call }.to change { charge.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it 'soft deletes all the related groups' do
      freeze_time do
        expect { destroy_service.call }.to change { group.reload.deleted_at }.from(nil).to(Time.current)
          .and change { group_property.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it 'enqueues a BillableMetrics::DeleteEventsJob' do
      expect do
        destroy_service.call
      end.to have_enqueued_job(BillableMetrics::DeleteEventsJob).with(billable_metric)
    end

    it 'enqueues a Invoices::RefreshBatchJob' do
      invoice = create(:invoice, :draft)
      create(:invoice_subscription, subscription:, invoice:)

      expect do
        destroy_service.call
      end.to have_enqueued_job(Invoices::RefreshBatchJob).with([invoice.id])
    end

    it 'calls SegmentTrackJob' do
      destroy_service.call

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'billable_metric_deleted',
        properties: {
          code: billable_metric.code,
          name: billable_metric.name,
          description: billable_metric.description,
          aggregation_type: billable_metric.aggregation_type,
          aggregation_property: billable_metric.field_name,
          organization_id: billable_metric.organization_id,
        },
      )
    end

    context 'when billable metric is not found' do
      it 'returns an error' do
        result = described_class.new(metric: nil).call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('billable_metric_not_found')
      end
    end
  end
end
