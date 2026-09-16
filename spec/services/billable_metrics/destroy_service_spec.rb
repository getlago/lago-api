# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::DestroyService do
  subject(:destroy_service) { described_class.new(metric: billable_metric) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:subscription) { create(:subscription) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

  before do
    charge

    allow(Invoices::RefreshDraftService).to receive(:call)
  end

  describe "#call" do
    it "soft deletes the billable metric" do
      freeze_time do
        expect { destroy_service.call }.to change(BillableMetric, :count).by(-1)
          .and change { billable_metric.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "soft deletes all the related charges" do
      freeze_time do
        expect { destroy_service.call }.to change { charge.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "soft deletes all the related alerts" do
      alert = create(:billable_metric_current_usage_amount_alert, billable_metric:, organization:)
      freeze_time do
        expect { destroy_service.call }.to change { alert.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it "enqueues a BillableMetricFilters::DestroyAllJob" do
      expect { destroy_service.call }
        .to have_enqueued_job(BillableMetricFilters::DestroyAllJob).with(billable_metric.id)
    end

    it "enqueues a billable_metric.deleted webhook" do
      destroy_service.call

      expect(SendWebhookJob).to have_been_enqueued.with("billable_metric.deleted", billable_metric)
    end

    it "marks invoice as ready to be refreshed" do
      invoice = create(:invoice, :draft)
      create(:invoice_subscription, subscription:, invoice:)

      expect { destroy_service.call }.to change { invoice.reload.ready_to_be_refreshed }.to(true)
    end

    context "when billable metric is not found" do
      it "returns an error" do
        result = described_class.new(metric: nil).call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("billable_metric_not_found")
      end
    end

    context "when a product filter value references the metric's filters" do
      let(:filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu]) }
      let(:product_filter) { create(:product_filter, organization:) }

      before do
        create(:product_filter_value, organization:, product_filter:, billable_metric_filter: filter, value: "eu")
      end

      it "blocks the deletion without discarding the metric" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.messages[:billable_metric]).to eq(["referenced_by_product_filter"])
        expect(billable_metric.reload).not_to be_discarded
      end

      it "does not enqueue the filters destroy job" do
        expect { destroy_service.call }.not_to have_enqueued_job(BillableMetricFilters::DestroyAllJob)
      end
    end
  end

  describe ".call" do
    it "produces an activity log" do
      described_class.call(metric: billable_metric)

      expect(Utils::ActivityLog).to have_produced("billable_metric.deleted").after_commit.with(billable_metric)
    end
  end
end
