# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::DeleteForMetricService, clickhouse: true, transaction: false do
  subject(:service) { described_class.new(billable_metric:) }

  let(:billable_metric) { create(:billable_metric, :deleted) }
  let(:subscription) { create(:subscription) }

  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

  let(:event_timestamp) { (billable_metric.deleted_at || Time.current) - 1.minute }
  let(:event) { create(:event, code: billable_metric.code, subscription_id: subscription.id, organization_id: billable_metric.organization_id, timestamp: event_timestamp, created_at: event_timestamp) }
  let(:not_impacted_event) { create(:event, subscription_id: subscription.id, organization_id: billable_metric.organization_id, timestamp: event_timestamp, created_at: event_timestamp) }

  before do
    charge
    event
    not_impacted_event
  end

  describe "call" do
    it "deletes related events" do
      expect { service.call }
        .to change { event.reload.deleted_at }.from(nil).to(billable_metric.deleted_at)

      expect(not_impacted_event.reload.deleted_at).to be_nil
    end

    context "with new-style external_subscription based events" do
      let(:event) { create(:event, code: billable_metric.code, external_subscription_id: subscription.external_id, organization_id: billable_metric.organization_id, timestamp: event_timestamp, created_at: event_timestamp) }
      let(:not_impacted_event) { create(:event, external_subscription_id: SecureRandom.uuid, organization_id: billable_metric.organization_id, timestamp: event_timestamp, created_at: event_timestamp) }

      it "deletes related events" do
        expect { service.call }.to change { event.reload.deleted_at }.from(nil).to(billable_metric.deleted_at)

        expect(not_impacted_event.reload.deleted_at).to be_nil
      end
    end

    context "when the charge is discarded" do
      before { charge.discard }

      it "still deletes related events" do
        expect { service.call }
          .to change { event.reload.deleted_at }.from(nil).to(billable_metric.deleted_at)
      end
    end

    context "when the charges span several charge batches" do
      let(:other_subscription) { create(:subscription) }
      let(:other_charge) { create(:standard_charge, plan: other_subscription.plan, billable_metric:) }
      let(:other_event) do
        create(:event, code: billable_metric.code, subscription_id: other_subscription.id, organization_id: billable_metric.organization_id, timestamp: event_timestamp, created_at: event_timestamp)
      end

      before do
        stub_const("#{described_class}::CHARGE_BATCH_SIZE", 1)
        other_charge
        other_event
      end

      it "deletes events for subscriptions across every charge batch" do
        service.call

        expect(event.reload.deleted_at).to eq(billable_metric.deleted_at)
        expect(other_event.reload.deleted_at).to eq(billable_metric.deleted_at)
      end
    end

    context "when a plan's charges span several charge batches" do
      let(:second_charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

      before do
        stub_const("#{described_class}::CHARGE_BATCH_SIZE", 1)
        second_charge
        allow(Subscriptions::ChargeCacheService).to receive(:expire_for_subscriptions).and_call_original
      end

      it "processes the subscription twice but deletes its events idempotently" do
        expect { service.call }
          .to change { event.reload.deleted_at }.from(nil).to(billable_metric.deleted_at)

        expect(Subscriptions::ChargeCacheService).to have_received(:expire_for_subscriptions).twice
        expect(not_impacted_event.reload.deleted_at).to be_nil
      end
    end

    context "with unrelated events" do
      let(:other_metric) { create(:billable_metric, organization: billable_metric.organization) }
      let(:other_metric_charge) { create(:standard_charge, plan: subscription.plan, billable_metric: other_metric) }
      let(:other_metric_event) do
        create(:event, code: other_metric.code, subscription_id: subscription.id, organization_id: billable_metric.organization_id, timestamp: event_timestamp, created_at: event_timestamp)
      end
      let(:other_organization) { create(:organization) }
      let(:other_org_event) do
        create(:event, code: billable_metric.code, external_subscription_id: subscription.external_id, organization_id: other_organization.id, timestamp: event_timestamp, created_at: event_timestamp)
      end

      before do
        other_metric_charge
        other_metric_event
        other_org_event
      end

      it "only deletes events matching the metric code and organization" do
        service.call

        expect(event.reload.deleted_at).to eq(billable_metric.deleted_at)
        expect(other_metric_event.reload.deleted_at).to be_nil
        expect(other_org_event.reload.deleted_at).to be_nil
      end
    end

    context "when event is received after billable_metric deletion" do
      let(:event) do
        create(
          :event,
          code: billable_metric.code,
          subscription_id: subscription.id,
          created_at: billable_metric.deleted_at + 1.hour
        )
      end

      it "does not delete events received after the metric deletion" do
        expect { service.call }.not_to change { event.reload.deleted_at }
      end
    end

    context "when billable_metric is not deleted" do
      let(:billable_metric) { create(:billable_metric) }

      it "does not delete events" do
        expect(service.call!).to be_success
        expect(event.reload.deleted_at).to be_nil
        expect(not_impacted_event.reload.deleted_at).to be_nil
      end
    end

    context "with charge-usage cache invalidation" do
      it "expires the charge-usage cache for each (subscription, charge) of each affected subscription" do
        allow(Subscriptions::ChargeCacheService).to receive(:expire_for_subscription_charge).and_call_original

        service.call

        expect(Subscriptions::ChargeCacheService)
          .to have_received(:expire_for_subscription_charge)
          .with(subscription: having_attributes(id: subscription.id), charge: having_attributes(id: charge.id))
      end

      context "when a cached usage value has already been written", cache: :memory do
        let(:cache_key) do
          [
            "charge-usage",
            Subscriptions::ChargeCacheService::CACHE_KEY_VERSION,
            charge.id,
            subscription.id,
            charge.updated_at.iso8601
          ].join("/")
        end

        before do
          Rails.cache.write(cache_key, '[{"amount_cents":3000}]')
        end

        it "invalidates the cached usage so a subsequent read recomputes without the deleted metric" do
          expect(Rails.cache.exist?(cache_key)).to be true

          service.call

          expect(Rails.cache.exist?(cache_key)).to be false
        end
      end
    end

    context "with clickhouse events" do
      include_context "with clickhouse availability"

      let(:ch_event) do
        create(
          :clickhouse_events_raw,
          organization_id: billable_metric.organization_id,
          code: billable_metric.code,
          external_subscription_id: subscription.external_id,
          ingested_at: event_timestamp
        )
      end

      let(:not_impacted_ch_event) do
        create(
          :clickhouse_events_raw,
          organization_id: billable_metric.organization_id,
          external_subscription_id: SecureRandom.uuid,
          ingested_at: event_timestamp
        )
      end

      let(:other_code_ch_event) do
        create(
          :clickhouse_events_raw,
          organization_id: billable_metric.organization_id,
          code: "#{billable_metric.code}_other",
          external_subscription_id: subscription.external_id,
          ingested_at: event_timestamp
        )
      end

      let(:other_org_ch_event) do
        create(
          :clickhouse_events_raw,
          organization_id: SecureRandom.uuid,
          code: billable_metric.code,
          external_subscription_id: subscription.external_id,
          ingested_at: event_timestamp
        )
      end

      let(:ch_enriched_event) do
        create(
          :clickhouse_events_enriched,
          organization_id: billable_metric.organization_id,
          code: billable_metric.code,
          external_subscription_id: subscription.external_id,
          enriched_at: event_timestamp
        )
      end

      let(:not_impacted_ch_enriched_event) do
        create(
          :clickhouse_events_enriched,
          organization_id: billable_metric.organization_id,
          external_subscription_id: SecureRandom.uuid,
          enriched_at: event_timestamp
        )
      end

      let(:ch_enriched_expanded_event) do
        create(
          :clickhouse_events_enriched_expanded,
          organization_id: billable_metric.organization_id,
          code: billable_metric.code,
          external_subscription_id: subscription.external_id,
          enriched_at: event_timestamp
        )
      end

      let(:not_impacted_ch_enriched_expanded_event) do
        create(
          :clickhouse_events_enriched_expanded,
          organization_id: billable_metric.organization_id,
          external_subscription_id: SecureRandom.uuid,
          enriched_at: event_timestamp
        )
      end

      before do
        # Force ALTER TABLE DELETE mutations to run synchronously so the test can
        # observe the deletion immediately. In production this stays at "0" (async).
        stub_const("#{described_class}::CLICKHOUSE_MUTATIONS_SYNC", "2")

        ch_event
        not_impacted_ch_event
        other_code_ch_event
        other_org_ch_event
        ch_enriched_event
        not_impacted_ch_enriched_event
        ch_enriched_expanded_event
        not_impacted_ch_enriched_expanded_event
      end

      it "deletes matching clickhouse events_raw" do
        service.call

        expect(Clickhouse::EventsRaw.where(transaction_id: ch_event.transaction_id).count)
          .to eq(0)
        expect(Clickhouse::EventsRaw.where(transaction_id: not_impacted_ch_event.transaction_id).count)
          .to eq(1)
        expect(Clickhouse::EventsRaw.where(transaction_id: other_code_ch_event.transaction_id).count)
          .to eq(1)
        expect(Clickhouse::EventsRaw.where(transaction_id: other_org_ch_event.transaction_id).count)
          .to eq(1)
      end

      it "deletes matching clickhouse events_enriched" do
        service.call

        expect(Clickhouse::EventsEnriched.where(transaction_id: ch_enriched_event.transaction_id).count)
          .to eq(0)
        expect(Clickhouse::EventsEnriched.where(transaction_id: not_impacted_ch_enriched_event.transaction_id).count)
          .to eq(1)
      end

      it "deletes matching clickhouse events_enriched_expanded" do
        service.call

        expect(Clickhouse::EventsEnrichedExpanded.where(transaction_id: ch_enriched_expanded_event.transaction_id).count)
          .to eq(0)
        expect(Clickhouse::EventsEnrichedExpanded.where(transaction_id: not_impacted_ch_enriched_expanded_event.transaction_id).count)
          .to eq(1)
      end

      context "when the subscription list exceeds CLICKHOUSE_BATCH_SIZE" do
        # delete_clickhouse_events slices the id list into CLICKHOUSE_BATCH_SIZE
        # chunks before inlining it into the ALTER TABLE … DELETE statement,
        # so a query never blows past ClickHouse's `max_query_size`. Stubbing
        # the constant to 1 forces two subscriptions to be sliced across two
        # CH queries per table × three tables = 6 calls.
        let(:second_subscription) { create(:subscription, customer: subscription.customer, plan: subscription.plan) }

        before do
          second_subscription
          stub_const("#{described_class}::CLICKHOUSE_BATCH_SIZE", 1)
          allow(::Clickhouse::BaseRecord.connection).to receive(:execute).and_call_original
        end

        it "slices the IN(?) list into CLICKHOUSE_BATCH_SIZE chunks" do
          service.call

          expect(::Clickhouse::BaseRecord.connection).to have_received(:execute).exactly(6).times
        end
      end

      context "with clickhouse events received after the metric deletion" do
        let(:late_ch_event) do
          create(
            :clickhouse_events_raw,
            organization_id: billable_metric.organization_id,
            code: billable_metric.code,
            external_subscription_id: subscription.external_id,
            ingested_at: billable_metric.deleted_at + 1.hour
          )
        end

        before { late_ch_event }

        it "does not delete events with timestamp after the metric deletion" do
          service.call

          expect(Clickhouse::EventsRaw.where(transaction_id: late_ch_event.transaction_id).count)
            .to eq(1)
        end
      end
    end
  end
end
