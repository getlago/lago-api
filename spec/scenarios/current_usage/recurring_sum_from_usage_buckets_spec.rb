# frozen_string_literal: true

require "rails_helper"

describe "Recurring sum current usage from usage buckets", clickhouse: true, transaction: false do
  include_context "with realtime usage availability"

  let(:organization) do
    create(:organization, webhook_url: nil, clickhouse_events_store: true, feature_flags:, premium_integrations:)
  end
  # The reads where the events count an event the buckets do not have yet
  let(:events_only_reads) { {} }
  let(:feature_flags) { %w[recurring_aggregation_snapshots persisted_recurring_values realtime_usage realtime_usage_recurring_sum] }
  let(:premium_integrations) { [] }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:plan) { create(:plan, organization:, amount_cents: 0, interval: "monthly") }
  let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "amount") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}) }
  # Buckets the pipeline has written, by the columns the table replaces rows on
  let(:buckets) { {} }
  # What each UsageBucketStore built for a usage read answered: "served", or why it fell back
  let(:bucket_reads) { [] }

  before do
    allow(Events::Stores::UsageBucketStore).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap do |store|
        allow(store).to receive(:recurring_fallback_reason).and_wrap_original do |reason, period|
          reason.call(period).tap { bucket_reads << (it || "served") }
        end
      end
    end
  end

  def subscription
    customer.subscriptions.order(:created_at).last
  end

  def start_subscription
    travel_to(Time.utc(2026, 3, 1)) do
      charge
      create_subscription({external_customer_id: customer.external_id, external_id: customer.external_id, plan_code: plan.code})
    end
  end

  # `bucketed: false` is an event the pipeline has not written yet, so the buckets and the events differ
  def send_event(amount, at:, timestamp: at, bucketed: true, **properties)
    travel_to(at) do
      create_clickhouse_event(
        code: billable_metric.code,
        external_subscription_id: customer.external_id,
        transaction_id: SecureRandom.uuid,
        timestamp:,
        properties: {amount:, **properties},
        decimal_value: amount.to_d,
        enriched_at: Time.current
      )
      write_bucket(amount, timestamp:, properties: properties.stringify_keys) if bucketed
    end
  end

  # As the pipeline does: under the subscription the event is dated in, with every pricing key, "" when
  # absent, the wallet key only for an event carrying one, and the whole bucket written again on each
  # event. Inserts run one after another, so the latest gets the highest `ver` and replaces the others.
  def write_bucket(amount, timestamp:, properties:)
    subscription = customer.subscriptions.where(started_at: ..timestamp).order(:started_at).last
    subscription_charge = subscription.plan.charges.find_by!(billable_metric:)
    grouped_by = Array(subscription_charge.pricing_group_keys).index_with { properties[it].to_s }
      .merge(properties.slice("target_wallet_code"))
    bucket = RealtimeUsage.floor_to_bucket(timestamp)

    row = buckets[[subscription.id, subscription_charge.id, grouped_by, bucket]] ||= {units: 0, events_count: 0, last_event_at: timestamp}
    row[:units] += amount
    row[:events_count] += 1
    row[:last_event_at] = [row[:last_event_at], timestamp].max

    create(
      :clickhouse_usage_bucket,
      organization:, customer:, subscription:, billable_metric:,
      charge: subscription_charge,
      bucket:,
      grouped_by: grouped_by.to_json,
      target_wallet_code: grouped_by["target_wallet_code"],
      aggregation_type: "sum",
      units: row[:units].to_s,
      events_count: row[:events_count],
      last_event_at: row[:last_event_at],
      last_ingested_at: Time.current
    )
  end

  def bill_at(time)
    travel_to(time) { perform_billing }
  end

  def usage_at(time)
    bucket_reads.clear
    usage = travel_to(time) { fetch_current_usage(customer:, subscription:) }[:customer_usage][:charges_usage].sole

    groups = usage[:grouped_usage].to_h do
      [it[:grouped_by].to_h.stringify_keys, [BigDecimal(it[:units]), it[:events_count]]]
    end

    {
      amount_cents: usage[:amount_cents],
      units: BigDecimal(usage[:units]),
      events_count: usage[:events_count],
      groups: groups.presence,
      buckets: bucket_reads.uniq
    }.compact
  end

  shared_examples "the same usage with the recurring flag off" do
    it "computes the current usage" do
      expect(usage_reads).to eq(expected_reads)
    end

    context "with the recurring sum flag off" do
      let(:feature_flags) { super() - %w[realtime_usage_recurring_sum] }

      it "computes the current usage from the events" do
        expect(usage_reads).to eq(expected_reads.to_h { |read, usage| [read, usage.merge(events_only_reads.fetch(read, {}), buckets: [])] })
      end
    end
  end

  describe "with a recurring sum over three periods" do
    def usage_reads
      start_subscription
      send_event(10, at: Time.utc(2026, 3, 5))
      send_event(3, at: Time.utc(2026, 3, 10))
      march = usage_at(Time.utc(2026, 3, 20))
      bill_at(Time.utc(2026, 4, 1, 1))

      april_without_event = usage_at(Time.utc(2026, 4, 5))
      send_event(5, at: Time.utc(2026, 4, 15))
      send_event(2, at: Time.utc(2026, 4, 15, 0, 5))
      send_event(1, at: Time.utc(2026, 4, 18), bucketed: false)
      april = usage_at(Time.utc(2026, 4, 20))

      # Dated in March, ingested after the snapshot of March
      send_event(7, at: Time.utc(2026, 4, 22), timestamp: Time.utc(2026, 3, 20))
      april_after_late_event = usage_at(Time.utc(2026, 4, 25))
      # In the last bucket before the May window and the first one of it
      send_event(1, at: Time.utc(2026, 4, 30, 23, 55))
      send_event(1, at: Time.utc(2026, 5, 1, 0, 5))
      bill_at(Time.utc(2026, 5, 1, 1))

      send_event(4, at: Time.utc(2026, 5, 10))
      may = usage_at(Time.utc(2026, 5, 20))

      {march:, april_without_event:, april:, april_after_late_event:, may:}
    end

    let(:expected_reads) do
      {
        # No snapshot before the first period
        march: {amount_cents: 1300, units: 13, events_count: 2, buckets: ["no_period"]},
        # An empty window adds nothing to the March snapshot
        april_without_event: {amount_cents: 1300, units: 13, events_count: 2, buckets: ["served"]},
        # The 5 and the 2 share a bucket; the 1 of 18 April is not in the buckets yet
        april: {amount_cents: 2000, units: 13 + 5 + 2, events_count: 4, buckets: ["served"]},
        # The March snapshot misses the late 7, so the events answer, with the unbucketed 1
        april_after_late_event: {amount_cents: 2800, units: 13 + 7 + 5 + 2 + 1, events_count: 6, buckets: ["late_ingestion"]},
        # The April snapshot counts the late 7, the unbucketed 1 and the 1 of 30 April, so the buckets complete it again
        may: {amount_cents: 3400, units: 29 + 1 + 4, events_count: 9, buckets: ["served"]}
      }
    end
    let(:events_only_reads) { {april: {amount_cents: 2100, units: 13 + 5 + 2 + 1, events_count: 5}} }

    include_examples "the same usage with the recurring flag off"
  end

  describe "with a plan upgrade during the period" do
    let(:upgraded_plan) { create(:plan, organization:, amount_cents: 1000, interval: "monthly") }
    let(:upgraded_charge) { create(:standard_charge, plan: upgraded_plan, billable_metric:, properties: {amount: "2"}) }
    let(:expected_reads) do
      {
        # The March snapshot of the previous subscription plus the 5 of the new one, at $2. The buckets
        # never see the previous subscription, so they are not read for it.
        april: {amount_cents: 3600, units: 13 + 5, events_count: 3, buckets: []}
      }
    end

    def usage_reads
      start_subscription
      travel_to(Time.utc(2026, 3, 1)) { upgraded_charge }
      send_event(10, at: Time.utc(2026, 3, 5))
      send_event(3, at: Time.utc(2026, 3, 10))
      bill_at(Time.utc(2026, 4, 1, 1))

      travel_to(Time.utc(2026, 4, 15, 12)) do
        create_subscription({external_customer_id: customer.external_id, external_id: customer.external_id, plan_code: upgraded_plan.code})
      end
      send_event(5, at: Time.utc(2026, 4, 20))

      {april: usage_at(Time.utc(2026, 4, 25))}
    end

    include_examples "the same usage with the recurring flag off"
  end

  describe "with a downgrade at the end of the period" do
    let(:plan) { create(:plan, organization:, amount_cents: 1000, interval: "monthly") }
    let(:downgraded_plan) { create(:plan, organization:, amount_cents: 0, interval: "monthly") }
    let(:downgraded_charge) { create(:standard_charge, plan: downgraded_plan, billable_metric:, properties: {amount: "2"}) }
    let(:expected_reads) do
      {
        # The March snapshot of the previous subscription is adjacent to the April window, but the late 7
        # is in a bucket of the previous subscription, which the history of the new one never reads.
        april: {amount_cents: 5000, units: 13 + 7 + 5, events_count: 4, buckets: []}
      }
    end

    def usage_reads
      start_subscription
      travel_to(Time.utc(2026, 3, 1)) { downgraded_charge }
      send_event(10, at: Time.utc(2026, 3, 5))
      send_event(3, at: Time.utc(2026, 3, 10))
      travel_to(Time.utc(2026, 3, 15)) do
        create_subscription({external_customer_id: customer.external_id, external_id: customer.external_id, plan_code: downgraded_plan.code})
      end
      # The downgrade starts when the billing run activates it: on the period boundary, the March
      # snapshot is adjacent to the window of the new subscription
      bill_at(Time.utc(2026, 4, 1))

      send_event(5, at: Time.utc(2026, 4, 15))
      # Dated in March, ingested after the snapshot of March
      send_event(7, at: Time.utc(2026, 4, 22), timestamp: Time.utc(2026, 3, 20))

      {april: usage_at(Time.utc(2026, 4, 25))}
    end

    include_examples "the same usage with the recurring flag off"
  end

  describe "with a grouped charge targeting wallets" do
    let(:premium_integrations) { %w[events_targeting_wallets] }
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, accepts_target_wallet: true, properties: {amount: "1", pricing_group_keys: ["workspace"]})
    end
    let(:expected_reads) do
      {
        april: {
          amount_cents: 2000,
          units: 13 + 5 + 2,
          events_count: 4,
          groups: {
            {"workspace" => "a", "target_wallet_code" => "W"} => [10 + 5, 2],
            {"workspace" => "b", "target_wallet_code" => nil} => [3, 1],
            {"workspace" => nil, "target_wallet_code" => "W"} => [2, 1]
          },
          buckets: ["served"]
        },
        april_after_late_event: {
          amount_cents: 2800,
          units: 13 + 7 + 5 + 2 + 1,
          events_count: 6,
          groups: {
            {"workspace" => "a", "target_wallet_code" => "W"} => [10 + 5 + 1, 3],
            {"workspace" => "b", "target_wallet_code" => nil} => [3 + 7, 2],
            {"workspace" => nil, "target_wallet_code" => "W"} => [2, 1]
          },
          buckets: ["late_ingestion"]
        }
      }
    end
    # The unbucketed 1 of 17 April
    let(:events_only_reads) do
      {
        april: {
          amount_cents: 2100,
          units: 13 + 5 + 2 + 1,
          events_count: 5,
          groups: {
            {"workspace" => "a", "target_wallet_code" => "W"} => [10 + 5 + 1, 3],
            {"workspace" => "b", "target_wallet_code" => nil} => [3, 1],
            {"workspace" => nil, "target_wallet_code" => "W"} => [2, 1]
          }
        }
      }
    end

    def usage_reads
      start_subscription
      send_event(10, at: Time.utc(2026, 3, 5), workspace: "a", target_wallet_code: "W")
      send_event(3, at: Time.utc(2026, 3, 10), workspace: "b")
      bill_at(Time.utc(2026, 4, 1, 1))

      send_event(5, at: Time.utc(2026, 4, 15), workspace: "a", target_wallet_code: "W")
      send_event(2, at: Time.utc(2026, 4, 16), target_wallet_code: "W")
      send_event(1, at: Time.utc(2026, 4, 17), workspace: "a", target_wallet_code: "W", bucketed: false)
      april = usage_at(Time.utc(2026, 4, 20))

      send_event(7, at: Time.utc(2026, 4, 22), timestamp: Time.utc(2026, 3, 20), workspace: "b")
      april_after_late_event = usage_at(Time.utc(2026, 4, 25))

      {april:, april_after_late_event:}
    end

    include_examples "the same usage with the recurring flag off"
  end
end
