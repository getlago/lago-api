# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::FetchProductBucketsService, clickhouse: {clean_before: true} do
  subject(:fetch) { described_class.call(contract:, billing_segments:) }

  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: %w[realtime_usage product_catalog])
  end
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:product) { create(:product, :metered, organization:, billable_metric:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }
  let(:effective_date) { Date.new(2027, 2, 1) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, effective_date:, billing_anchor_date: effective_date)
  end
  let(:started_at) { Time.zone.parse("2027-02-01") }
  let(:ended_at) { BillingSegment.inclusive_end(Time.zone.parse("2027-03-01")) }
  let(:rate_properties) { {"amount" => "1"} }
  let(:billing_segment) { segment_for(contract_rate_card) }
  let(:billing_segments) { [billing_segment] }

  def segment_for(card, properties: rate_properties)
    build(:billing_segment, organization:, customer:, contract:, contract_rate_card: card,
      rate_properties: properties, cycle_started_at: started_at, started_at:, ended_at:)
  end

  def create_bucket(bucket:, units: "10.0", events_count: 2, bucket_product: product, **attributes)
    create(
      :clickhouse_product_usage_bucket,
      contract:, product: bucket_product, bucket:, units:, events_count:,
      aggregation_type: "sum", last_event_at: bucket,
      **attributes
    )
  end

  def totals_for(card, product_filter_id: "")
    fetch.usage_buckets.aggregation_result_for(charge_id: card.id, charge_filter_id: product_filter_id)
  end

  describe "#call" do
    it "sums the buckets of the segment's window, keyed by its card" do
      create_bucket(bucket: started_at, units: "10.0", events_count: 2)
      create_bucket(bucket: Time.zone.parse("2027-02-28 23:45"), units: "5.5", events_count: 1)
      create_bucket(bucket: started_at - 15.minutes, units: "99.0", events_count: 9)
      create_bucket(bucket: Time.zone.parse("2027-03-01"), units: "99.0", events_count: 9)

      totals = totals_for(contract_rate_card)

      expect(totals.value).to eq(BigDecimal("15.5")) # 10.0 + 5.5, the buckets either side of the window left out
      expect(totals.events_count).to eq(3)
    end

    it "bills only the rows matching no filter on a card without one" do
      product_filter = create(:product_filter, :with_values, organization:, product:)
      create_bucket(bucket: started_at, units: "10.0")
      create_bucket(bucket: started_at, units: "3.0", product_filters: [product_filter])

      expect(totals_for(contract_rate_card).value).to eq(BigDecimal("10.0"))
    end

    it "ignores the buckets of other contracts and the ones the sink deleted" do
      create_bucket(bucket: started_at, units: "10.0", events_count: 2)
      create_bucket(bucket: started_at + 15.minutes, units: "4.0", events_count: 1, is_deleted: 1)
      create(:clickhouse_product_usage_bucket, contract: create(:contract, organization:), product:,
        bucket: started_at, units: "8.0", aggregation_type: "sum")

      expect(totals_for(contract_rate_card).value).to eq(BigDecimal("10.0"))
    end

    it "reads with FINAL, so a re-upserted bucket is not counted twice" do
      create_bucket(bucket: started_at, units: "10.0", events_count: 2)
      create_bucket(bucket: started_at, units: "12.0", events_count: 3)

      expect(totals_for(contract_rate_card).value).to eq(BigDecimal("12.0"))
    end

    context "with overlapping product filters" do
      # An event in the EU on the free tier matches both filters. Without prices, region = eu
      # wins: one value against tier's two.
      let(:region_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
      let(:tier_filter) { create(:billable_metric_filter, billable_metric:, key: "tier", values: %w[free premium]) }
      let(:eu_filter) { filter_on(region_filter, "eu") }
      let(:any_tier_filter) { filter_on(tier_filter, nil) }
      let(:eu_card) { filtered_card(eu_filter, eu_effective_date) }
      let(:any_tier_card) { filtered_card(any_tier_filter, effective_date) }
      let(:eu_effective_date) { effective_date }
      let(:billing_segments) { [segment_for(eu_card), segment_for(any_tier_card)] }

      def filter_on(metric_filter, value)
        create(:product_filter, organization:, product:).tap do |filter|
          create(:product_filter_value, organization:, product_filter: filter, billable_metric_filter: metric_filter, value:)
        end
      end

      def filtered_card(product_filter, card_effective_date)
        filtered_rate_card = create(:rate_card, organization:, product:, product_filter:, currency: "EUR")
        create(:contract_rate_card, organization:, contract:, rate_card: filtered_rate_card,
          effective_date: card_effective_date, billing_anchor_date: card_effective_date)
      end

      before do
        create_bucket(bucket: started_at, units: "10.0", product_filters: [eu_filter, any_tier_filter])
        create_bucket(bucket: started_at, units: "3.0", product_filters: [any_tier_filter])
      end

      it "bills the rows matching both on the filter Rails picks for the segment" do
        expect(totals_for(eu_card, product_filter_id: eu_filter.id).value).to eq(BigDecimal("10.0"))
        expect(totals_for(any_tier_card, product_filter_id: any_tier_filter.id).value).to eq(BigDecimal("3.0"))
      end

      context "when the better filter's card starts after the segment" do
        let(:eu_effective_date) { Date.new(2027, 3, 1) }
        let(:billing_segments) { [segment_for(any_tier_card)] }

        it "bills them on the filter the segment prices" do
          # Only tier = any is priced in February (BillingSegment#priced_product_filter_ids).
          expect(totals_for(any_tier_card, product_filter_id: any_tier_filter.id).value).to eq(BigDecimal("13.0")) # 10.0 + 3.0
        end
      end

      context "when the segment prices neither filter" do
        # A card started before the segment is not priced in it (BillingSegment#priced_product_filter_ids).
        let(:eu_effective_date) { Date.new(2027, 1, 1) }
        let(:any_tier_card) { filtered_card(any_tier_filter, Date.new(2027, 1, 1)) }

        it "bills them on the filter the usual precedence picks" do
          expect(totals_for(eu_card, product_filter_id: eu_filter.id).value).to eq(BigDecimal("10.0"))
          expect(totals_for(any_tier_card, product_filter_id: any_tier_filter.id).value).to eq(BigDecimal("3.0"))
        end
      end
    end

    context "with two segments reading the same product and filter" do
      let(:other_rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }
      let(:other_contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card, effective_date:,
          billing_anchor_date: effective_date)
      end
      let(:billing_segments) { [billing_segment, segment_for(other_contract_rate_card)] }

      it "reads the rows for each, as each segment reads its own events" do
        create_bucket(bucket: started_at)

        expect(totals_for(contract_rate_card).value).to eq(BigDecimal("10.0"))
        expect(totals_for(other_contract_rate_card).value).to eq(BigDecimal("10.0"))
      end
    end

    context "with segments of one product on different windows" do
      let(:other_rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }
      let(:other_contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card, effective_date:,
          billing_anchor_date: Date.new(2027, 2, 15))
      end
      let(:other_segment) do
        build(:billing_segment, organization:, customer:, contract:, contract_rate_card: other_contract_rate_card,
          rate_properties:, cycle_started_at: Time.zone.parse("2027-02-15"), started_at: Time.zone.parse("2027-02-15"),
          ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-03-15")))
      end
      let(:billing_segments) { [billing_segment, other_segment] }

      it "sums each segment over its own window" do
        create_bucket(bucket: started_at, units: "1.0")
        create_bucket(bucket: Time.zone.parse("2027-02-20"), units: "2.0")
        create_bucket(bucket: Time.zone.parse("2027-03-10"), units: "4.0")

        expect(totals_for(contract_rate_card).value).to eq(BigDecimal("3.0")) # 1.0 + 2.0
        expect(totals_for(other_contract_rate_card).value).to eq(BigDecimal("6.0")) # 2.0 + 4.0
      end
    end

    context "with a window off the bucket walls" do
      let(:started_at) { Time.zone.parse("2027-02-01 10:07") }

      it "reads nothing, as a bucket is summed whole" do
        create_bucket(bucket: Time.zone.parse("2027-02-01 10:00"))

        expect(fetch.usage_buckets).to be_nil
      end
    end

    context "with pricing group keys" do
      let(:rate_properties) { {"amount" => "1", "pricing_group_keys" => ["region"]} }

      it "returns one result per group, regrouped on the segment's keys" do
        create_bucket(bucket: started_at, units: "10.0", events_count: 2, grouped_by: {"region" => "eu"}.to_json)
        create_bucket(bucket: started_at, units: "1.0", events_count: 1, grouped_by: {"region" => ""}.to_json)
        create_bucket(bucket: started_at + 15.minutes, units: "4.0", events_count: 1, grouped_by: {"region" => "", "model" => "a"}.to_json)

        grouped = fetch.usage_buckets.grouped_aggregation_results_for(charge_id: contract_rate_card.id, charge_filter_id: "")

        expect(grouped.map { [it.groups, it.value, it.events_count] }).to match_array(
          [
            [{"region" => "eu"}, BigDecimal("10.0"), 2],
            [{"region" => nil}, BigDecimal("5.0"), 2] # the empty value (1.0) and the row grouped by another key too (4.0)
          ]
        )
      end

      it "reads nothing when a row was written without one of the segment's keys" do
        create_bucket(bucket: started_at, units: "10.0", events_count: 2, grouped_by: {"region" => "eu"}.to_json)
        create_bucket(bucket: started_at + 15.minutes, units: "4.0", events_count: 1, grouped_by: "{}")

        expect(fetch).to be_success
        expect(fetch.usage_buckets).to be_nil
      end
    end

    context "with a max aggregation" do
      it "takes the greatest units across the window" do
        create_bucket(bucket: started_at, units: "10.0", aggregation_type: "max")
        create_bucket(bucket: started_at + 15.minutes, units: "4.0", aggregation_type: "max")

        expect(totals_for(contract_rate_card).value).to eq(BigDecimal("10.0"))
      end
    end

    context "without any segment" do
      let(:billing_segments) { [] }

      it "reads nothing" do
        expect(fetch.usage_buckets).to be_nil
      end
    end

    context "when realtime usage is disabled for the organization" do
      let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: %w[product_catalog]) }

      it "reads nothing" do
        create_bucket(bucket: started_at)

        expect(fetch.usage_buckets).to be_nil
      end
    end

    context "when clickhouse is unreachable" do
      before do
        allow(Clickhouse::ProductUsageBucket).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(Sentry).to receive(:capture_exception)
      end

      it "fails, so the caller knows the buckets were not read rather than empty" do
        expect(fetch).to be_failure
        expect(fetch.error.code).to eq("usage_buckets_read_failure")
        expect(fetch.usage_buckets).to be_nil
        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(ActiveRecord::ConnectionNotEstablished))
      end
    end
  end
end
