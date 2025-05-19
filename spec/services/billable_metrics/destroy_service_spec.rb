# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::DestroyService, type: :service do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:subscription) { create(:subscription) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

  before do
    charge

    allow(BillableMetrics::DeleteEventsJob).to receive(:perform_later).and_call_original
    allow(Invoices::RefreshDraftService).to receive(:call)
    allow(Utils::ActivityLog).to receive(:produce).and_call_original
  end

  describe ".call" do
    it "soft deletes the billable metric" do
      freeze_time do
        expect { described_class.call(metric: billable_metric) }.to change(BillableMetric, :count).by(-1)
          .and change { billable_metric.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "soft deletes all the related charges" do
      freeze_time do
        expect { described_class.call(metric: billable_metric) }.to change { charge.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "enqueues a BillableMetricFilters::DestroyAllJob" do
      expect { destroy_service.call }
        .to have_enqueued_job(BillableMetricFilters::DestroyAllJob).with(billable_metric.id)
    end

    it "enqueues a BillableMetrics::DeleteEventsJob" do
      expect do
        described_class.call(metric: billable_metric)
      end.to have_enqueued_job(BillableMetrics::DeleteEventsJob).with(billable_metric)
    end

    it "marks invoice as ready to be refreshed" do
      invoice = create(:invoice, :draft)
      create(:invoice_subscription, subscription:, invoice:)

      expect { described_class.call(metric: billable_metric) }.to change { invoice.reload.ready_to_be_refreshed }.to(true)
    end

    it "produces an activity log" do
      described_class.call(metric: billable_metric)

      expect(Utils::ActivityLog).to have_received(:produce).with(billable_metric, "billable_metric.deleted")
    end

    context "when billable metric is not found" do
      it "returns an error" do
        result = described_class.call(metric: nil)

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("billable_metric_not_found")
      end
    end
  end
end
