# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::ContractUsageBucketsProvider, clickhouse: {clean_before: true} do
  subject(:provider) { described_class.new(contract:, billing_context:) }

  include_context "with realtime usage availability"

  let(:feature_flags) { %w[product_catalog realtime_usage] }
  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags:) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01"), terminated_at:) }
  let(:billing_context) { Billing::Context.from(contract:) }
  let(:timestamp) { Time.zone.parse("2027-02-10 12:00:00") }

  let(:aggregation_type) { :count_agg }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type:, field_name: "value") }
  let(:region) { create(:billable_metric_filter, billable_metric:, organization:, key: "region", values: %w[eu us]) }
  let(:tier) { create(:billable_metric_filter, billable_metric:, organization:, key: "tier", values: %w[gold silver]) }
  let(:product) { create(:product, :metered, organization:, billable_metric:) }

  let(:rate_model) { "standard" }
  let(:rate_from) { Time.zone.parse("2027-01-01") }
  let(:rate_properties) { {"amount" => "1"} }
  let(:billing_timing) { :arrears }
  let(:terminated_at) { nil }
  let(:card_filter) { nil }
  let(:contract_rate_card) { attach_card(card_filter) }

  let(:metered_item) do
    card = contract_rate_card
    billable_segment = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule.segment_covering(timestamp)
    billing_segment = BillingSegments::BuildEventSegmentService.call!(contract_rate_card: card, billable_segment:).billing_segment

    Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:, product_filter: card_filter)
  end
  let(:boundaries) { metered_item.aggregation_boundaries }

  def product_filter(values)
    create(:product_filter, organization:, product:).tap do |filter|
      values.each do |metric_filter, value|
        create(:product_filter_value, organization:, product_filter: filter, billable_metric_filter: metric_filter, value:)
      end
    end
  end

  def attach_card(filter)
    rate_card = create(:rate_card, organization:, product:, product_filter: filter, currency: "EUR", billing_timing:)
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_from, rate_model:, rate_properties:)
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
  end

  before { ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = "product_events_raw" }
  after { ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = nil }

  describe "#unsupported_reason" do
    subject(:reason) { provider.unsupported_reason(metered_item:, boundaries:) }

    it { is_expected.to be_nil }

    context "when realtime usage is off for the organization" do
      let(:feature_flags) { %w[product_catalog] }

      it { is_expected.to eq("disabled") }
    end

    context "when the organization is not on the product events pipeline" do
      before { ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = nil }

      it { is_expected.to eq("disabled") }
    end

    context "with a charge" do
      let(:plan) { create(:plan, organization:) }
      let(:charge) { create(:standard_charge, plan:, billable_metric:) }
      let(:metered_item) { Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries: {}) }
      let(:boundaries) { {from_datetime: Time.zone.parse("2027-02-01"), to_datetime: Time.zone.parse("2027-02-28").end_of_day} }

      it { is_expected.to eq("not_a_billing_segment") }
    end

    context "with a percentage rate" do
      let(:rate_model) { "percentage" }
      let(:rate_properties) { {"rate" => "1"} }

      it { is_expected.to eq("unsupported_charge_model") }
    end

    context "with a unique count metric" do
      let(:aggregation_type) { :unique_count_agg }

      it { is_expected.to eq("unsupported_aggregation_type") }
    end

    context "with a card billed in advance" do
      let(:billing_timing) { :advance }

      it { is_expected.to eq("pay_in_advance") }
    end

    context "with a recurring metric" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }

      it { is_expected.to eq("recurring_metric") }
    end

    context "with a max timestamp" do
      let(:boundaries) { metered_item.aggregation_boundaries.merge(max_timestamp: timestamp) }

      it { is_expected.to eq("max_timestamp") }
    end

    context "with a contract terminated inside a bucket" do
      let(:terminated_at) { Time.zone.parse("2027-02-20 10:07") }

      it { is_expected.to eq("unaligned_window") }
    end

    context "with a contract terminated on a bucket wall" do
      let(:terminated_at) { Time.zone.parse("2027-02-20 10:15") }

      it { is_expected.to be_nil }
    end

    context "with a customer timezone half an hour off UTC" do
      let(:customer) { create(:customer, organization:, timezone: "Asia/Kolkata", currency: "EUR") }

      it { is_expected.to be_nil }
    end

    context "with a card on a filter overlapped by a filter the contract does not price" do
      # BillingSegment#priced_product_filter_ids takes the cards effective during the segment.
      let(:timestamp) { Time.zone.parse("2027-01-10 12:00:00") }
      let(:card_filter) { product_filter(region => "eu") }

      before { product_filter(region => "eu", tier => "gold") }

      # The stream bills an EU gold event on the unpriced, more specific filter and drops it,
      # where Rails bills it on the priced EU filter.
      it { is_expected.to eq("filter_precedence") }
    end

    context "with a card on a filter overlapped by a filter the contract prices" do
      let(:timestamp) { Time.zone.parse("2027-01-10 12:00:00") }
      let(:card_filter) { product_filter(region => "eu") }

      before { attach_card(product_filter(region => "eu", tier => "gold")) }

      it { is_expected.to be_nil }
    end

    context "with a card on a filter that outranks an unpriced overlapping filter" do
      let(:timestamp) { Time.zone.parse("2027-01-10 12:00:00") }
      let(:card_filter) { product_filter(region => "eu", tier => "gold") }

      before { product_filter(region => "eu") }

      it { is_expected.to be_nil }
    end

    context "with a default card next to an unpriced filter" do
      before { product_filter(region => "eu") }

      it { is_expected.to be_nil }
    end
  end

  describe "#store_for" do
    subject(:store) { provider.store_for(metered_item:, boundaries:, filters:) }

    let(:filters) { {} }

    context "with buckets for the window" do
      before do
        create(:clickhouse_product_usage_bucket, contract:, product:, bucket: Time.zone.parse("2027-02-03"),
          aggregation_type: "count", units: "4", events_count: 4)
      end

      it "answers from the buckets" do
        expect(store).to be_a(Events::Stores::UsageBucketStore)
        expect(store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 4, events_count: 4))
      end

      it "reads the buckets once per window" do
        provider.store_for(metered_item:, boundaries:, filters:)
        allow(RealtimeUsage::FetchProductBucketsService).to receive(:call).and_call_original

        provider.store_for(metered_item:, boundaries:, filters:)

        expect(RealtimeUsage::FetchProductBucketsService).not_to have_received(:call)
      end

      context "with a pay in advance event" do
        let(:filters) { {event: build(:common_event)} }

        it "reads the events" do
          expect(store).to be_a(Events::Stores::ClickhouseStore)
        end
      end
    end

    context "without buckets for the window" do
      it "reads the events" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end

    context "when the buckets cannot be read" do
      before do
        allow(Clickhouse::ProductUsageBucket).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(Sentry).to receive(:capture_exception)
      end

      it "reads the events" do
        expect(store).to be_a(Events::Stores::ClickhouseStore)
      end
    end
  end
end
