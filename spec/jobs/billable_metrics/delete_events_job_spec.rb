# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::DeleteEventsJob, transaction: false, clickhouse: true do
  let(:billable_metric) { create(:billable_metric, :deleted) }
  let(:subscription) { create(:subscription) }

  it "deletes related events" do
    create(:standard_charge, plan: subscription.plan, billable_metric:)
    not_impacted_event = create(:event, subscription_id: subscription.id)
    event = create(:event, code: billable_metric.code, subscription_id: subscription.id)

    freeze_time do
      expect { described_class.perform_now(billable_metric) }
        .to change { event.reload.deleted_at }.from(nil).to(Time.current)

      expect(not_impacted_event.reload.deleted_at).to be_nil
    end
  end

  it "deletes new-style external_subscription based events" do
    create(:standard_charge, plan: subscription.plan, billable_metric:)
    not_impacted_event = create(:event, external_subscription_id: SecureRandom.uuid, organization_id: billable_metric.organization_id)
    event = create(:event, code: billable_metric.code, external_subscription_id: subscription.external_id, organization_id: billable_metric.organization_id)

    freeze_time do
      expect { described_class.perform_now(billable_metric) }
        .to change { event.reload.deleted_at }.from(nil).to(Time.current)

      expect(not_impacted_event.reload.deleted_at).to be_nil
    end
  end

  it "deletes new-style external_subscription based events stored in clickhouse" do
    create(:standard_charge, plan: subscription.plan, billable_metric:)
    not_impacted_event = create(:clickhouse_events_raw, external_subscription_id: SecureRandom.uuid, organization_id: billable_metric.organization_id)
    event = create(:clickhouse_events_raw, code: billable_metric.code, external_subscription_id: subscription.external_id, organization_id: billable_metric.organization_id)

    freeze_time do
      described_class.perform_now(billable_metric)
      expect(Clickhouse::EventsRaw.find_by(transaction_id: event.transaction_id)).to eq(nil)
      expect(Clickhouse::EventsRaw.find_by(transaction_id: not_impacted_event.transaction_id)).not_to eq(nil)
    end
  end

  it "deletes new-style external_subscription based events_enriched stored in clickhouse" do
    create(:standard_charge, plan: subscription.plan, billable_metric:)
    not_impacted_event = create(:clickhouse_events_enriched, external_subscription_id: SecureRandom.uuid, organization_id: billable_metric.organization_id)
    event = create(:clickhouse_events_enriched, code: billable_metric.code, external_subscription_id: subscription.external_id, organization_id: billable_metric.organization_id)

    freeze_time do
      described_class.perform_now(billable_metric)
      expect(Clickhouse::EventsEnriched.find_by(transaction_id: event.transaction_id)).to eq(nil)
      expect(Clickhouse::EventsEnriched.find_by(transaction_id: not_impacted_event.transaction_id)).not_to eq(nil)
    end
  end
end
