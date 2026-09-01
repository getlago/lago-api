# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Provider do
  subject(:provider) { described_class.new(organization:, subscription:, boundaries:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:boundaries) { {from_datetime: Time.current.beginning_of_month, to_datetime: Time.current} }

  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

  let(:bucket_set) do
    Events::Stores::UsageBucketSet.new(
      totals: {[charge.id, ""] => Events::Stores::UsageBucketSet::Totals.new(units: BigDecimal("10"), events_count: 2)}
    )
  end

  describe "#store_for" do
    it "returns a store configured for the charge and the computation window" do
      store = provider.store_for(charge:)

      expect(store).to be_a(Events::Stores::PostgresStore)
      expect(store.code).to eq(billable_metric.code)
      expect(store.subscription).to eq(subscription)
      expect(store.boundaries).to eq(boundaries)
      expect(store.deduplicate).to be(false)
    end

    it "forwards the filters" do
      charge_filter = create(:charge_filter, charge:)
      filters = {charge_id: charge.id, charge_filter:, matching_filters: {"key" => ["value"]}, ignored_filters: []}

      store = provider.store_for(charge:, filters:)

      expect(store.filters).to eq(filters)
      expect(store.matching_filters).to eq({"key" => ["value"]})
    end

    it "returns a plain store even when the computation carries usage buckets" do
      provider = described_class.new(organization:, subscription:, boundaries:, usage_buckets: bucket_set)

      expect(provider.store_for(charge:)).to be_a(Events::Stores::PostgresStore)
    end

    it "mints one instance per call, so aggregators cannot share per-charge state" do
      first = provider.store_for(charge:)
      second = provider.store_for(charge:)

      expect(first).not_to be(second)

      first.aggregation_property = "total_count"
      expect(second.aggregation_property).to be_nil
    end
  end

  describe "#usage_buckets" do
    it "is nil when the computation was built without buckets" do
      expect(provider.usage_buckets).to be_nil
    end

    it "exposes the set it was built with" do
      provider = described_class.new(organization:, subscription:, boundaries:, usage_buckets: bucket_set)

      expect(provider.usage_buckets).to eq(bucket_set)
    end

    it "keeps an empty set, which the prefetch built after finding no usage" do
      empty_set = Events::Stores::UsageBucketSet.new
      provider = described_class.new(organization:, subscription:, boundaries:, usage_buckets: empty_set)

      expect(provider.usage_buckets).to eq(empty_set)
    end
  end

  describe "#precomputed_options_for" do
    subject(:provider) do
      described_class.new(organization:, subscription:, boundaries:, usage_buckets: bucket_set, current_usage: true)
    end

    include_context "with realtime usage availability"

    let(:organization) do
      create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
    end
    let(:totals) { Events::Stores::UsageBucketSet::Totals.new(units: BigDecimal("42.5"), events_count: 7) }
    let(:bucket_set) { Events::Stores::UsageBucketSet.new(totals: {[charge.id, ""] => totals}) }

    context "when the organization is not enabled for realtime usage" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it "reads events" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "when the organization still reads the postgres events store" do
      let(:organization) { create(:organization, feature_flags: ["realtime_usage"]) }

      it "reads events, because the buckets and the postgres events would disagree" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "when the deployment kill switch is off" do
      let(:risingwave_usage_enabled) { nil }

      it "reads events" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "with a sum_agg charge" do
      let(:billable_metric) { create(:sum_billable_metric, organization:) }

      it "serves the units" do
        options = provider.precomputed_options_for(charge:)

        expect(options[:precomputed_aggregation].value).to eq(BigDecimal("42.5"))
        expect(options[:precomputed_grouped_aggregations]).to eq([])
      end
    end

    context "with a count_agg charge" do
      let(:totals) { Events::Stores::UsageBucketSet::Totals.new(units: BigDecimal("7"), events_count: 7) }

      it "serves the units, which the pipeline already counts one per event" do
        options = provider.precomputed_options_for(charge:)

        expect(options[:precomputed_aggregation].value).to eq(7)
      end
    end

    context "with a prorated charge" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
      let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, prorated: true) }

      it "reads events" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "with a recurring metric" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }

      it "reads events, because the units carry over from before this window" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "with an aggregation the buckets cannot reconstruct" do
      let(:billable_metric) { create(:max_billable_metric, organization:) }

      it "reads events" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "with a unique_count metric" do
      let(:billable_metric) { create(:unique_count_billable_metric, organization:) }

      it "reads events, because distincts do not recompose across buckets" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "when the computation carries no buckets" do
      subject(:provider) { described_class.new(organization:, subscription:, boundaries:, current_usage: true) }

      it "reads events" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "when the computation is not current usage" do
      subject(:provider) do
        described_class.new(organization:, subscription:, boundaries:, usage_buckets: bucket_set)
      end

      it "reads events, because the buckets always lag behind the window they close" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
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
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "when the store is already scoped to one group" do
      it "reads events, because the totals answer for the whole charge" do
        options = provider.precomputed_options_for(charge:, filters: {grouped_by_values: {"region" => "us"}})

        expect(options).to eq({})
      end
    end

    context "with a pay-in-advance event" do
      it "reads events" do
        event = create(:event, organization_id: organization.id, subscription_id: subscription.id)

        expect(provider.precomputed_options_for(charge:, filters: {event:})).to eq({})
      end
    end

    context "with no charge filter" do
      it "looks the charge up under the empty-string sentinel the pipeline writes" do
        options = provider.precomputed_options_for(charge:, filters: {charge_filter: ChargeFilter.new(charge:)})

        expect(options[:precomputed_aggregation].value).to eq(BigDecimal("42.5"))
      end
    end

    context "with a persisted charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:bucket_set) { Events::Stores::UsageBucketSet.new(totals: {[charge.id, charge_filter.id] => totals}) }

      it "serves the row of that filter" do
        options = provider.precomputed_options_for(charge:, filters: {charge_filter:})

        expect(options[:precomputed_aggregation].value).to eq(BigDecimal("42.5"))
      end

      it "answers zero for the unfiltered charge" do
        expect(provider.precomputed_options_for(charge:)[:precomputed_aggregation].value).to eq(0)
      end
    end

    context "when the window holds no bucket at all" do
      let(:bucket_set) { Events::Stores::UsageBucketSet.new }

      it "reads events, because a pipeline gap and an absence of usage look the same" do
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end

    context "with a presentation breakdown" do
      it "reads events, which the breakdown queries anyway" do
        expect(provider.precomputed_options_for(charge:, filters: {presentation_by: ["region"]})).to eq({})
      end
    end

    context "when the read is narrowed to one pricing group" do
      it "reads events, because the totals answer for every group of the charge" do
        options = provider.precomputed_options_for(charge:, filters: {filter_by_group: {"workspace" => ["A"]}})

        expect(options).to eq({})
      end
    end
  end

  describe "#serves?" do
    subject(:provider) do
      described_class.new(organization:, subscription:, boundaries:, usage_buckets: bucket_set, current_usage: true)
    end

    include_context "with realtime usage availability"

    let(:organization) do
      create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
    end

    it "answers the same question as the precomputed options, so the charge cache cannot disagree" do
      expect(provider.serves?(charge:)).to be(true)
      expect(provider.precomputed_options_for(charge:)).not_to eq({})
    end

    context "with an excluded charge" do
      let(:charge) { create(:percentage_charge, plan: subscription.plan, billable_metric:) }

      it "answers false, and the options stay empty" do
        expect(provider.serves?(charge:)).to be(false)
        expect(provider.precomputed_options_for(charge:)).to eq({})
      end
    end
  end

  describe "#plain_store" do
    it "returns a store with no metric code" do
      store = provider.plain_store

      expect(store).to be_a(Events::Stores::PostgresStore)
      expect(store.code).to be_nil
      expect(store.boundaries).to eq(boundaries)
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
