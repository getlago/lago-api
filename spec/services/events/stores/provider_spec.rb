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

      it "is true, because the stream deduplicates as well" do
        expect(provider.may_precompute?).to be(true)
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
    let(:totals) { Events::Stores::UsageBucketSet::Totals.new(aggregation_type: "sum_agg", units: BigDecimal("42.5"), events_count: 7, last_event_at: Time.current) }
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
      let(:totals) { Events::Stores::UsageBucketSet::Totals.new(aggregation_type: "count_agg", units: BigDecimal(7), events_count: 7, last_event_at: Time.current) }

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
      let(:billable_metric) { create(:weighted_sum_billable_metric, organization:) }

      it "reads events" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "with a max metric" do
      let(:billable_metric) { create(:max_billable_metric, organization:) }
      let(:totals) do
        Events::Stores::UsageBucketSet::Totals.new(
          aggregation_type: "max_agg", units: BigDecimal(12), events_count: 3, last_event_at: Time.current
        )
      end

      it "serves it from the buckets" do
        expect(store).to be_a(Events::Stores::UsageBucketStore)
        expect(store.max.value).to eq(BigDecimal(12))
      end
    end

    context "with a latest metric" do
      let(:billable_metric) { create(:latest_billable_metric, organization:) }
      let(:totals) do
        Events::Stores::UsageBucketSet::Totals.new(
          aggregation_type: "latest_agg", units: BigDecimal(12), events_count: 3, last_event_at: Time.current
        )
      end

      it "serves it from the buckets" do
        expect(store).to be_a(Events::Stores::UsageBucketStore)
        expect(store.last.value).to eq(BigDecimal(12))
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

      it "serves the buckets, as the stream deduplicates as well" do
        expect(store).to be_a(Events::Stores::UsageBucketStore)
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

    describe "#serves_whole_charge_from_buckets?" do
      subject(:serves_whole_charge) do
        provider.serves_whole_charge_from_buckets?(metered_item:, boundaries:)
      end

      let(:pricing_bucket_filter) { create(:charge_filter, charge:) }

      # The pre-filtering of a charge this accepts is resolved from the buckets, so a pricing
      # bucket the store then delegates would be zeroed by a list that never saw its events.
      it "is true only when the store serves every pricing bucket of that charge" do
        expect(serves_whole_charge).to be(true)
        expect(store).to be_a(Events::Stores::UsageBucketStore)
        expect(provider.store_for(metered_item:, boundaries:, filters: {charge_filter: pricing_bucket_filter}))
          .to be_a(Events::Stores::UsageBucketStore)
      end

      context "with a presentation breakdown on the charge" do
        let(:charge) do
          create(
            :standard_charge,
            plan: subscription.plan,
            billable_metric:,
            properties: {amount: "1", presentation_group_keys: [{"value" => "region"}]}
          )
        end

        # Every pricing bucket of the charge carries the breakdown, which reads events, so the
        # charge is delegated as a whole rather than one bucket at a time.
        it "is false, and the store delegates that charge as well" do
          expect(serves_whole_charge).to be(false)
          expect(provider.store_for(metered_item:, boundaries:, filters: {presentation_by: ["region"]}))
            .to be_a(Events::Stores::ClickhouseStore)
        end

        context "when the caller asked for no breakdown at all" do
          subject(:provider) do
            described_class.new(
              organization:,
              billing_context:,
              serve_current_usage_from_buckets: true,
              boundaries: billing_boundaries,
              usage_filters: UsageFilters::WITHOUT_PRESENTATION_FILTER,
              charges: [charge]
            )
          end

          # The wallet refresh narrows the breakdown to nothing, so no pricing bucket of the charge
          # reads an event and the buckets answer the charge whole.
          it "is true, as the store serves that charge" do
            expect(serves_whole_charge).to be(true)
            expect(provider.store_for(metered_item:, boundaries:, filters: {presentation_by: []}))
              .to be_a(Events::Stores::UsageBucketStore)
          end
        end
      end

      context "with a charge the buckets cannot answer" do
        let(:charge) { create(:percentage_charge, plan: subscription.plan, billable_metric:) }

        it "is false, without reading clickhouse" do
          expect(serves_whole_charge).to be(false)
          expect(RealtimeUsage::FetchBucketsService).not_to have_received(:call)
        end
      end
    end

    describe "#precomputed_filter_ids" do
      subject(:precomputed_filter_ids) { provider.precomputed_filter_ids(charge_id: charge.id) }

      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:bucket_set) do
        Events::Stores::UsageBucketSet.new(
          totals: {[charge.id, ""] => totals, [charge.id, charge_filter.id] => totals}
        )
      end

      it "returns the filters of the charge the buckets hold usage for, the default one as nil" do
        expect(precomputed_filter_ids).to match_array([nil, charge_filter.id])
      end

      context "when the buckets hold nothing for the charge" do
        let(:bucket_set) { Events::Stores::UsageBucketSet.new(totals: {[create(:standard_charge).id, ""] => totals}) }

        it "returns no filter, which leaves every fee of the charge at zero units" do
          expect(precomputed_filter_ids).to be_empty
        end
      end

      context "when no bucket was fetched" do
        before do
          allow(RealtimeUsage::FetchBucketsService).to receive(:call)
            .and_return(RealtimeUsage::FetchBucketsService::Result.new)
        end

        it "returns no filter" do
          expect(precomputed_filter_ids).to be_empty
        end
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
