# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Provider do
  subject(:provider) { described_class.new(organization:, billing_context:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:billing_context) { Billing::Context.from(subscription:) }
  let(:boundaries) { {from_datetime: Time.current.beginning_of_month, to_datetime: Time.current} }

  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
  let(:metered_item) do
    Fees::ChargeService::MeteredItem.from_charge(
      charge:,
      boundaries: BillingPeriodBoundaries.new(
        from_datetime: boundaries[:from_datetime],
        to_datetime: boundaries[:to_datetime],
        charges_from_datetime: boundaries[:from_datetime],
        charges_to_datetime: boundaries[:to_datetime],
        charges_duration: nil,
        timestamp: nil
      )
    )
  end

  describe "#store_for" do
    it "returns a store configured for the metered item and the given window" do
      store = provider.store_for(metered_item:, boundaries:)

      expect(store).to be_a(Events::Stores::PostgresStore)
      expect(store.code).to eq(billable_metric.code)
      expect(store.billing_context).to eq(billing_context)
      expect(store.boundaries).to eq(boundaries)
      expect(store.deduplicate).to be(false)
    end

    it "forwards the filters" do
      charge_filter = create(:charge_filter, charge:)
      filters = {charge_id: charge.id, charge_filter:, matching_filters: {"key" => ["value"]}, ignored_filters: []}

      store = provider.store_for(metered_item:, boundaries:, filters:)

      expect(store.filters).to eq(filters)
      expect(store.matching_filters).to eq({"key" => ["value"]})
    end

    it "takes the window per call, so one provider serves aggregations on different windows" do
      other_boundaries = boundaries.merge(max_timestamp: boundaries[:from_datetime] + 1.day)

      expect(provider.store_for(metered_item:, boundaries:).boundaries).to eq(boundaries)
      expect(provider.store_for(metered_item:, boundaries: other_boundaries).boundaries).to eq(other_boundaries)
    end

    it "mints one instance per call, so aggregators cannot share per-charge state" do
      first = provider.store_for(metered_item:, boundaries:)
      second = provider.store_for(metered_item:, boundaries:)

      expect(first).not_to be(second)

      first.aggregation_property = "total_count"
      expect(second.aggregation_property).to be_nil
    end
  end

  describe "#may_precompute?" do
    subject(:provider) do
      described_class.new(organization:, billing_context:, serve_current_usage_from_buckets: true)
    end

    include_context "with realtime usage availability"

    let(:organization) do
      create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
    end

    before { allow(RealtimeUsage::FetchBucketsService).to receive(:call) }

    it "is true when every gate that does not depend on a charge holds, without reading clickhouse" do
      expect(provider.may_precompute?).to be(true)
      expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
    end

    context "when the provider was not asked to serve the buckets" do
      subject(:provider) { described_class.new(organization:, billing_context:) }

      it "is false" do
        expect(provider.may_precompute?).to be(false)
      end
    end

    context "when the read is restricted to some pricing group values" do
      subject(:provider) do
        described_class.new(
          organization:,
          billing_context:,
          serve_current_usage_from_buckets: true,
          usage_filters: UsageFilters.new(filter_by_group: {"region" => "us"})
        )
      end

      it "is false" do
        expect(provider.may_precompute?).to be(false)
      end
    end

    context "when the read covers the whole lifetime of the subscription" do
      subject(:provider) do
        described_class.new(
          organization:,
          billing_context:,
          serve_current_usage_from_buckets: true,
          usage_filters: UsageFilters.new(full_usage: true)
        )
      end

      it "is false" do
        expect(provider.may_precompute?).to be(false)
      end
    end

    # The caller skips per-charge work on the strength of this answer, so an organization the
    # feature is off for has to be refused here rather than one store at a time.
    context "when realtime usage is disabled for the organization" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it "is false" do
        expect(provider.may_precompute?).to be(false)
      end
    end

    context "when the organization deduplicates its events" do
      let(:organization) do
        create(
          :organization,
          clickhouse_events_store: true,
          clickhouse_deduplication_enabled: true,
          feature_flags: ["realtime_usage"]
        )
      end

      it "is false" do
        expect(provider.may_precompute?).to be(false)
      end
    end
  end

  describe "#store_for, with the usage buckets" do
    subject(:provider) do
      described_class.new(
        organization:,
        billing_context:,
        serve_current_usage_from_buckets: true,
        boundaries: billing_boundaries,
        charges: [charge]
      )
    end

    include_context "with realtime usage availability"

    let(:organization) do
      create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
    end
    let(:billable_metric) { create(:sum_billable_metric, organization:) }
    let(:billing_boundaries) { metered_item.boundaries }
    let(:totals) { Events::Stores::UsageBucketSet::Totals.new(units: BigDecimal("42.5"), events_count: 7) }
    let(:bucket_set) { Events::Stores::UsageBucketSet.new(totals: {[charge.id, ""] => totals}) }
    let(:store) { provider.store_for(metered_item:, boundaries:, filters:) }
    let(:filters) { {} }

    before do
      allow(RealtimeUsage::FetchBucketsService).to receive(:call)
        .and_return(RealtimeUsage::FetchBucketsService::Result.new.tap { it.usage_buckets = bucket_set })
    end

    it "wraps the store in the bucket-backed one" do
      expect(store).to be_a(Events::Stores::UsageBucketStore)
      expect(store.sum.value).to eq(BigDecimal("42.5"))
      expect(store.__getobj__).to be_a(Events::Stores::ClickhouseStore)
    end

    it "reads the buckets once, however many charges it is asked about" do
      provider.store_for(metered_item:, boundaries:)
      provider.store_for(metered_item:, boundaries:)

      expect(RealtimeUsage::FetchBucketsService).to have_received(:call).once
    end

    context "without the opt-in" do
      subject(:provider) do
        described_class.new(organization:, billing_context:, boundaries: billing_boundaries)
      end

      it "reads events, without asking clickhouse for buckets" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
        expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
      end
    end

    context "when the organization is not enabled for realtime usage" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it "reads events, without asking clickhouse for buckets" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
        expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
      end
    end

    context "when the organization still reads the postgres events store" do
      let(:organization) { create(:organization, feature_flags: ["realtime_usage"]) }

      it "reads events, because the buckets and the postgres events would disagree" do
        expect(store).to be_a(Events::Stores::PostgresStore)
      end
    end

    context "when the deployment kill switch is off" do
      let(:realtime_usage_enabled) { nil }

      it "reads events" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with a count_agg charge" do
      let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
      let(:totals) { Events::Stores::UsageBucketSet::Totals.new(units: BigDecimal(7), events_count: 7) }

      it "serves the units, which the pipeline already counts one per event" do
        expect(store.count.value).to eq(7)
      end
    end

    context "with a prorated charge" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
      let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, prorated: true) }

      it "reads events" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with a recurring metric" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }

      it "reads events, because the units carry over from before this window" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with an aggregation the buckets cannot reconstruct" do
      let(:billable_metric) { create(:max_billable_metric, organization:) }

      it "reads events" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with a unique_count metric" do
      let(:billable_metric) { create(:unique_count_billable_metric, organization:) }

      it "reads events, because distincts do not recompose across buckets" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with an excluded charge model" do
      let(:charge) { create(:percentage_charge, plan: subscription.plan, billable_metric:) }

      it "reads events, without asking clickhouse for buckets" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
        expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
      end
    end

    context "when the organization deduplicates its clickhouse events" do
      let(:organization) do
        create(
          :organization,
          feature_flags: ["realtime_usage"],
          clickhouse_events_store: true,
          clickhouse_deduplication_enabled: true
        )
      end

      it "reads events, because the stream and the events store disagree by construction" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "when the store is already scoped to one group" do
      let(:filters) { {grouped_by_values: {"region" => "us"}} }

      it "reads events, because the totals answer for the whole charge" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with a pay-in-advance event" do
      let(:filters) { {event: create(:event, organization_id: organization.id, subscription_id: subscription.id)} }

      it "reads events" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with no charge filter" do
      let(:filters) { {charge_filter: ChargeFilter.new(charge:)} }

      it "looks the charge up under the empty-string sentinel the pipeline writes" do
        expect(store.sum.value).to eq(BigDecimal("42.5"))
      end
    end

    context "with a persisted charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:bucket_set) { Events::Stores::UsageBucketSet.new(totals: {[charge.id, charge_filter.id] => totals}) }
      let(:filters) { {charge_filter:} }

      it "serves the row of that filter" do
        expect(store.sum.value).to eq(BigDecimal("42.5"))
      end

      it "answers zero for the unfiltered charge" do
        expect(provider.store_for(metered_item:, boundaries:).sum.value).to eq(0)
      end
    end

    context "when the window holds no bucket at all" do
      let(:bucket_set) { Events::Stores::UsageBucketSet.new }

      it "reads events, as an empty set is no proof the pipeline wrote this window" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "when the window holds buckets for another charge only" do
      let(:bucket_set) { Events::Stores::UsageBucketSet.new(totals: {[create(:standard_charge).id, ""] => totals}) }

      it "serves no usage for this one, the written window proving the pipeline is not lagging" do
        expect(store).to be_a(Events::Stores::UsageBucketStore)
        expect(store.sum.value).to eq(0)
      end
    end

    context "when the prefetch refused the window" do
      before do
        allow(RealtimeUsage::FetchBucketsService).to receive(:call)
          .and_return(RealtimeUsage::FetchBucketsService::Result.new)
      end

      it "reads events, as nothing was fetched to serve from" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "when the prefetch failed to read clickhouse" do
      let(:failed_result) do
        RealtimeUsage::FetchBucketsService::Result.new
          .service_failure!(code: "usage_buckets_read_failure", message: "connection reset")
      end

      before do
        allow(RealtimeUsage::FetchBucketsService).to receive(:call).and_return(failed_result)
      end

      it "reads events rather than raising, as an unreachable clickhouse makes usage slow, not broken" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "when the window is frozen at a past timestamp" do
      let(:boundaries) do
        {from_datetime: Time.current.beginning_of_month, to_datetime: Time.current, max_timestamp: 1.hour.ago}
      end

      it "reads events, without asking clickhouse for buckets" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
        expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
      end
    end

    context "with a presentation breakdown" do
      let(:filters) { {presentation_by: ["region"]} }

      it "reads events, which the breakdown queries anyway" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "when the read is restricted to some pricing group values" do
      subject(:provider) do
        described_class.new(
          organization:,
          billing_context:,
          serve_current_usage_from_buckets: true,
          boundaries: billing_boundaries,
          usage_filters: UsageFilters.new(filter_by_group: {"region" => "us"})
        )
      end

      it "reads events, because the totals answer for the whole charge" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
        expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
      end
    end

    context "when the store is asked for another window than the one prefetched" do
      let(:other_window) { boundaries.merge(to_datetime: boundaries[:to_datetime] + 1.day) }

      it "reads events, as the buckets cover the window they were fetched for" do
        expect(provider.store_for(metered_item:, boundaries: other_window)).to be_a(Events::Stores::ClickhouseStore)
        expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
      end
    end

    context "when the provider was built without a window" do
      subject(:provider) do
        described_class.new(organization:, billing_context:, serve_current_usage_from_buckets: true)
      end

      it "reads events, having no window to have fetched buckets for" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with a billing segment" do
      let(:metered_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: billing_segment) }
      let(:billing_segment) { create(:billing_segment) }

      it "reads events, because the buckets are keyed by charge" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end
  end

  describe "#store_class" do
    it "resolves the postgres store by default" do
      expect(provider.store_class).to eq(Events::Stores::PostgresStore)
    end

    context "with a clickhouse organization" do
      include_context "with clickhouse availability"

      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it "resolves the clickhouse store" do
        expect(provider.store_class).to eq(Events::Stores::ClickhouseStore)
      end
    end

    context "with an active store override" do
      it "honors the override" do
        Events::Stores::StoreFactory.with_override(store_class: Events::Stores::ClickhouseStore, deduplicate: true) do
          expect(provider.store_class).to eq(Events::Stores::ClickhouseStore)
        end
      end
    end
  end

  describe "#deduplicate" do
    it "is false when the organization does not deduplicate" do
      expect(provider.deduplicate).to be(false)
    end

    context "when the organization deduplicates its clickhouse events" do
      let(:organization) do
        create(:organization, clickhouse_events_store: true, clickhouse_deduplication_enabled: true)
      end

      it "is true" do
        expect(provider.deduplicate).to be(true)
      end
    end

    context "with an active store override" do
      it "honors the override" do
        Events::Stores::StoreFactory.with_override(store_class: Events::Stores::PostgresStore, deduplicate: true) do
          expect(provider.deduplicate).to be(true)
        end
      end
    end
  end
end
