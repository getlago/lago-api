# frozen_string_literal: true

require "rails_helper"

describe "Recurring aggregation snapshots", transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, feature_flags:, clickhouse_events_store:) }
  let(:feature_flags) { [] }
  let(:clickhouse_events_store) { false }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:plan) { create(:plan, organization:, amount_cents: 0, interval: "monthly") }
  let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "amount") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}) }
  let(:read_periods) { {usage: [], invoice: []} }
  let(:march_billed_at) { Time.utc(2026, 4, 1, 1) }
  let(:march_watermark) { march_billed_at - RecurringAggregationSnapshot::WATERMARK_LAG }
  let(:march_snapshot) { Time.utc(2026, 3, 31).end_of_day.floor(6) }
  let(:april_snapshot) { Time.utc(2026, 4, 30).end_of_day.floor(6) }
  # One read per bucket, nil when it falls back to the full history
  let(:invoice_reads) { [nil, march_snapshot, april_snapshot] }
  let(:usage_reads) { [march_snapshot, april_snapshot] }

  before do
    allow(RecurringAggregationSnapshots::FetchService).to receive(:call!).and_wrap_original do |method, **args|
      method.call(**args).tap { read_periods[:invoice] << it.period&.to_datetime }
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

  def send_event(amount, at:, timestamp: at, **properties)
    travel_to(at) do
      params = {
        code: billable_metric.code,
        external_subscription_id: customer.external_id,
        timestamp: timestamp.to_i,
        properties: {amount:, **properties}
      }

      if organization.clickhouse_events_store?
        create_clickhouse_event(params.merge(timestamp:, transaction_id: SecureRandom.uuid, decimal_value: amount.to_d, enriched_at: Time.current))
      else
        create_event(params)
      end
    end
  end

  def bill_at(time)
    travel_to(time) do
      perform_billing
      last_invoice_fees
    end
  end

  def last_invoice_fees
    charge_fees(customer.invoices.where(created_at: Time.current).sole)
  end

  def usage_at(time)
    invoice_reads = read_periods[:invoice].size
    usage = travel_to(time) { fetch_current_usage(customer:, subscription:) }[:customer_usage][:charges_usage].sole
    read_periods[:usage].concat(read_periods[:invoice].slice!(invoice_reads..))

    {amount_cents: usage[:amount_cents], units: round_units(BigDecimal(usage[:units])), events_count: usage[:events_count]}
  end

  # The stores compute weighted sums with different decimal precisions
  def round_units(units)
    units.round(10)
  end

  def charge_fees(invoice)
    invoice.fees.charge.map do |fee|
      {
        filter: fee.charge_filter&.to_h,
        grouped_by: fee.grouped_by.presence,
        amount_cents: fee.amount_cents,
        units: round_units(fee.units),
        events_count: fee.events_count
      }.compact
    end.sort_by(&:to_s)
  end

  def written_snapshots
    RecurringAggregationSnapshot.where(organization:).includes(:charge_filter).map do |snapshot|
      {
        subscription_id: snapshot.subscription_id,
        charge_id: snapshot.charge_id,
        to: snapshot.to_datetime.to_date,
        filter: snapshot.charge_filter&.to_h,
        grouped_by: snapshot.grouped_by.presence,
        units: snapshot.units,
        events_count: snapshot.events_count
      }.compact
    end
  end

  def expected_snapshots
    subscription_id = subscription.id
    snapshots.map { {subscription_id:, charge_id: charge.id}.merge(it) }
  end

  # The event ingested at the watermark of the March invoice is in the March snapshot, so a delta reading
  # it too counts it twice. The one ingested after is billed in March but left to the delta.
  def send_sum_events
    send_event(10, at: Time.utc(2026, 3, 5))
    send_event(3, at: Time.utc(2026, 3, 10))
    send_event(2, at: march_watermark, timestamp: Time.utc(2026, 3, 31, 12))
    send_event(1, at: march_watermark + 2.minutes, timestamp: Time.utc(2026, 3, 31, 18))
  end

  # Three billed periods: March writes the first snapshot, April and May read from the previous one
  def bill
    start_subscription
    send_sum_events
    march_invoice = bill_at(march_billed_at)

    # Dated in March, ingested after the March invoice
    send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20))
    travel_to(Time.utc(2026, 4, 10)) { change_catalog }
    send_event(5, at: Time.utc(2026, 4, 15))
    april_usage = usage_at(Time.utc(2026, 4, 20))
    april_invoice = bill_at(Time.utc(2026, 5, 1, 1))

    send_event(4, at: Time.utc(2026, 5, 10))
    # May is not billed yet: the usage of June starts from the April snapshot
    june_usage = usage_at(Time.utc(2026, 6, 1, 0, 30))

    {march_invoice:, april_usage:, april_invoice:, june_usage:, may_invoice: bill_at(Time.utc(2026, 6, 1, 1))}
  end

  def change_catalog
  end

  shared_examples "bills the same with every snapshot flag" do
    context "with both flags off" do
      it "bills from the full history" do
        expect(bill).to eq(billed)
        expect(written_snapshots).to be_empty
        expect(read_periods).to eq(usage: [], invoice: [])
      end
    end

    context "with snapshot writes only" do
      let(:feature_flags) { %w[recurring_aggregation_snapshots] }

      it "writes the snapshots and bills from the full history" do
        expect(bill).to eq(billed)
        expect(written_snapshots).to match_array(expected_snapshots)
        expect(read_periods).to eq(usage: [], invoice: [])
      end
    end

    context "with snapshot writes and reads" do
      let(:feature_flags) { %w[recurring_aggregation_snapshots persisted_recurring_values] }

      it "bills what the full history bills, starting from the snapshots" do
        expect(bill).to eq(billed)
        expect(written_snapshots).to match_array(expected_snapshots)
        expect(read_periods).to eq(invoice: invoice_reads, usage: usage_reads)
      end
    end

    context "with snapshot reads only" do
      let(:feature_flags) { %w[persisted_recurring_values] }

      it "finds no snapshot and bills from the full history" do
        expect(bill).to eq(billed)
        expect(written_snapshots).to be_empty
        expect(read_periods.values.flatten.uniq).to eq([nil])
      end
    end
  end

  shared_examples "an in-arrears recurring sum" do
    let(:billed) do
      {
        march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
        april_usage: {amount_cents: 2800, units: 28, events_count: 6},
        april_invoice: [{amount_cents: 2800, units: 28, events_count: 6}],
        june_usage: {amount_cents: 3200, units: 32, events_count: 7},
        may_invoice: [{amount_cents: 3200, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: Date.new(2026, 3, 31), units: 15, events_count: 3},
        {to: Date.new(2026, 4, 30), units: 28, events_count: 6},
        {to: Date.new(2026, 5, 31), units: 32, events_count: 7}
      ]
    end

    include_examples "bills the same with every snapshot flag"

    context "with a snapshot edited after it was written" do
      let(:feature_flags) { %w[recurring_aggregation_snapshots persisted_recurring_values] }

      # A read that ignores the stored values bills the full history, as every other example expects
      def change_catalog
        RecurringAggregationSnapshot.where(organization:).sole.update!(units: 115, events_count: 4)
      end

      it "adds the stored values to the delta" do
        expect(bill).to eq(
          march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
          april_usage: {amount_cents: 12800, units: 128, events_count: 7},
          april_invoice: [{amount_cents: 12800, units: 128, events_count: 7}],
          june_usage: {amount_cents: 13200, units: 132, events_count: 8},
          may_invoice: [{amount_cents: 13200, units: 132, events_count: 8}]
        )
      end
    end
  end

  describe "with an in-arrears recurring sum" do
    it_behaves_like "an in-arrears recurring sum"

    context "with the ClickHouse store", clickhouse: true do
      let(:clickhouse_events_store) { true }

      it_behaves_like "an in-arrears recurring sum"
    end
  end

  shared_examples "a prorated recurring sum" do
    let(:charge) { create(:standard_charge, prorated: true, plan:, billable_metric:, properties: {amount: "1"}) }
    let(:billed) do
      {
        # Each event prorated over the days left in its period
        march_invoice: [{amount_cents: 1094, units: 16, events_count: 4}],
        april_usage: {amount_cents: 2567, units: 28, events_count: 6},
        april_invoice: [{amount_cents: 2567, units: 28, events_count: 6}],
        june_usage: {amount_cents: 3200, units: 32, events_count: 7},
        may_invoice: [{amount_cents: 3084, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: Date.new(2026, 3, 31), units: 15, events_count: 3},
        {to: Date.new(2026, 4, 30), units: 28, events_count: 6},
        {to: Date.new(2026, 5, 31), units: 32, events_count: 7}
      ]
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with a prorated recurring sum" do
    it_behaves_like "a prorated recurring sum"

    context "with the ClickHouse store", clickhouse: true do
      let(:clickhouse_events_store) { true }

      it_behaves_like "a prorated recurring sum"
    end
  end

  shared_examples "a recurring weighted sum" do
    let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:, field_name: "amount") }
    let(:billed) do
      {
        march_invoice: [{amount_cents: 1088, units: BigDecimal("10.8790322581"), events_count: 4}],
        # A weighted sum ignores events dated in a billed period
        april_usage: {amount_cents: 1867, units: BigDecimal("18.6666666667"), events_count: 1},
        april_invoice: [{amount_cents: 1867, units: BigDecimal("18.6666666667"), events_count: 1}],
        # Known defect: the usage after an unbilled period misses its events, the full history gives 25 units
        june_usage: {amount_cents: 2100, units: 21, events_count: 0},
        may_invoice: [{amount_cents: 2384, units: BigDecimal("23.8387096774"), events_count: 1}]
      }
    end
    let(:snapshots) do
      [
        {to: Date.new(2026, 3, 31), units: 16, events_count: 0},
        {to: Date.new(2026, 4, 30), units: 21, events_count: 0},
        {to: Date.new(2026, 5, 31), units: 25, events_count: 0}
      ]
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with a recurring weighted sum" do
    it_behaves_like "a recurring weighted sum"

    context "with the ClickHouse store", clickhouse: true do
      let(:clickhouse_events_store) { true }

      it_behaves_like "a recurring weighted sum"
    end
  end

  describe "with a percentage charge" do
    let(:charge) { create(:percentage_charge, plan:, billable_metric:, properties: {rate: "10", fixed_amount: "1"}) }
    let(:billed) do
      {
        # 10% of the units, plus $1 per event since the subscription started
        march_invoice: [{amount_cents: 560, units: 16, events_count: 4}],
        april_usage: {amount_cents: 880, units: 28, events_count: 6},
        april_invoice: [{amount_cents: 880, units: 28, events_count: 6}],
        june_usage: {amount_cents: 1020, units: 32, events_count: 7},
        may_invoice: [{amount_cents: 1020, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: Date.new(2026, 3, 31), units: 15, events_count: 3},
        {to: Date.new(2026, 4, 30), units: 28, events_count: 6},
        {to: Date.new(2026, 5, 31), units: 32, events_count: 7}
      ]
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with a charge filter added after a snapshot" do
    let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}).tap do |charge|
        eu_filter = create(:charge_filter, charge:, properties: {amount: "2"})
        create(:charge_filter_value, charge_filter: eu_filter, billable_metric_filter: region, values: ["eu"])
      end
    end
    let(:billed) do
      {
        march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
        april_usage: {amount_cents: 8400, units: 28, events_count: 6},
        april_invoice: [{filter: {"region" => ["us"]}, amount_cents: 8400, units: 28, events_count: 6}],
        june_usage: {amount_cents: 9600, units: 32, events_count: 7},
        may_invoice: [{filter: {"region" => ["us"]}, amount_cents: 9600, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: Date.new(2026, 3, 31), units: 15, events_count: 3},
        {to: Date.new(2026, 4, 30), units: 0, events_count: 0},
        {to: Date.new(2026, 4, 30), filter: {"region" => ["us"]}, units: 28, events_count: 6},
        {to: Date.new(2026, 5, 31), units: 0, events_count: 0},
        {to: Date.new(2026, 5, 31), filter: {"region" => ["us"]}, units: 32, events_count: 7}
      ]
    end
    # Every bucket of the charge reads the full history until a snapshot is written after the change
    let(:invoice_reads) { [nil, nil, nil, nil, nil, april_snapshot, april_snapshot, april_snapshot] }
    let(:usage_reads) { [nil, nil, nil, april_snapshot, april_snapshot, april_snapshot] }

    def send_event(amount, **)
      super(amount, region: "us", **)
    end

    def change_catalog
      create_plan_charge_filter(plan, charge.code, {invoice_display_name: "US", properties: {amount: "3"}, values: {region: ["us"]}})
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with a metric filter edited after a snapshot" do
    let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}).tap do |charge|
        all_regions = create(:charge_filter, charge:, properties: {amount: "2"})
        create(:charge_filter_value, charge_filter: all_regions, billable_metric_filter: region, values: [ChargeFilterValue::ALL_FILTER_VALUES])
      end
    end
    let(:billed) do
      {
        march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
        april_usage: {amount_cents: 5600, units: 28, events_count: 6},
        april_invoice: [{filter: {"region" => [ChargeFilterValue::ALL_FILTER_VALUES]}, amount_cents: 5600, units: 28, events_count: 6}],
        june_usage: {amount_cents: 6400, units: 32, events_count: 7},
        may_invoice: [{filter: {"region" => [ChargeFilterValue::ALL_FILTER_VALUES]}, amount_cents: 6400, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: Date.new(2026, 3, 31), units: 15, events_count: 3},
        {to: Date.new(2026, 4, 30), units: 0, events_count: 0},
        {to: Date.new(2026, 4, 30), filter: {"region" => [ChargeFilterValue::ALL_FILTER_VALUES]}, units: 28, events_count: 6},
        {to: Date.new(2026, 5, 31), units: 0, events_count: 0},
        {to: Date.new(2026, 5, 31), filter: {"region" => [ChargeFilterValue::ALL_FILTER_VALUES]}, units: 32, events_count: 7}
      ]
    end
    let(:invoice_reads) { [nil, nil, nil, nil, april_snapshot, april_snapshot] }
    let(:usage_reads) { [nil, nil, april_snapshot, april_snapshot] }

    def send_event(amount, **)
      super(amount, region: "fr", **)
    end

    # The all-values filter now matches the events of every closed period
    def change_catalog
      update_metric(billable_metric, {filters: [{key: "region", values: %w[eu us fr]}]})
    end

    include_examples "bills the same with every snapshot flag"
  end

  shared_examples "a recurring sum with filters and groups" do
    let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, properties: {amount: "1", pricing_group_keys: ["workspace"]}).tap do |charge|
        eu_filter = create(:charge_filter, charge:, properties: {amount: "2", pricing_group_keys: ["workspace"]})
        create(:charge_filter_value, charge_filter: eu_filter, billable_metric_filter: region, values: ["eu"])
      end
    end
    let(:billed) do
      {
        # Blank, whitespace and missing workspaces are one group
        march_invoice: [
          {filter: {"region" => ["eu"]}, grouped_by: {"workspace" => "a"}, amount_cents: 2400, units: 12, events_count: 2},
          {filter: {"region" => ["eu"]}, grouped_by: {"workspace" => nil}, amount_cents: 1400, units: 7, events_count: 2},
          {grouped_by: {"workspace" => "b"}, amount_cents: 700, units: 7, events_count: 2}
        ],
        april_usage: {amount_cents: 6400, units: 38, events_count: 8},
        april_invoice: [
          {filter: {"region" => ["eu"]}, grouped_by: {"workspace" => "a"}, amount_cents: 2400, units: 12, events_count: 2},
          {filter: {"region" => ["eu"]}, grouped_by: {"workspace" => nil}, amount_cents: 2800, units: 14, events_count: 3},
          {grouped_by: {"workspace" => "b"}, amount_cents: 1200, units: 12, events_count: 3}
        ],
        june_usage: {amount_cents: 7200, units: 42, events_count: 9},
        may_invoice: [
          {filter: {"region" => ["eu"]}, grouped_by: {"workspace" => "a"}, amount_cents: 3200, units: 16, events_count: 3},
          {filter: {"region" => ["eu"]}, grouped_by: {"workspace" => nil}, amount_cents: 2800, units: 14, events_count: 3},
          {grouped_by: {"workspace" => "b"}, amount_cents: 1200, units: 12, events_count: 3}
        ]
      }
    end
    let(:snapshots) do
      [
        {to: Date.new(2026, 3, 31), filter: {"region" => ["eu"]}, grouped_by: {"workspace" => "a"}, units: 12, events_count: 2},
        {to: Date.new(2026, 3, 31), filter: {"region" => ["eu"]}, grouped_by: {"workspace" => nil}, units: 7, events_count: 2},
        {to: Date.new(2026, 3, 31), grouped_by: {"workspace" => "b"}, units: 6, events_count: 1},
        {to: Date.new(2026, 4, 30), filter: {"region" => ["eu"]}, grouped_by: {"workspace" => "a"}, units: 12, events_count: 2},
        {to: Date.new(2026, 4, 30), filter: {"region" => ["eu"]}, grouped_by: {"workspace" => nil}, units: 14, events_count: 3},
        {to: Date.new(2026, 4, 30), grouped_by: {"workspace" => "b"}, units: 12, events_count: 3},
        {to: Date.new(2026, 5, 31), filter: {"region" => ["eu"]}, grouped_by: {"workspace" => "a"}, units: 16, events_count: 3},
        {to: Date.new(2026, 5, 31), filter: {"region" => ["eu"]}, grouped_by: {"workspace" => nil}, units: 14, events_count: 3},
        {to: Date.new(2026, 5, 31), grouped_by: {"workspace" => "b"}, units: 12, events_count: 3}
      ]
    end
    let(:invoice_reads) { [nil, nil, march_snapshot, march_snapshot, april_snapshot, april_snapshot] }
    let(:usage_reads) { [march_snapshot, march_snapshot, april_snapshot, april_snapshot] }

    def bill
      start_subscription
      send_event(10, at: Time.utc(2026, 3, 5), region: "eu", workspace: "a")
      send_event(3, at: Time.utc(2026, 3, 10), region: "eu", workspace: "")
      send_event(4, at: Time.utc(2026, 3, 12), region: "eu")
      send_event(6, at: Time.utc(2026, 3, 15), region: "us", workspace: "b")
      send_event(2, at: march_watermark, timestamp: Time.utc(2026, 3, 31, 12), region: "eu", workspace: "a")
      send_event(1, at: march_watermark + 2.minutes, timestamp: Time.utc(2026, 3, 31, 18), region: "us", workspace: "b")
      march_invoice = bill_at(march_billed_at)

      # Dated in March, ingested after the March invoice
      send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20), region: "eu", workspace: " ")
      send_event(5, at: Time.utc(2026, 4, 15), region: "us", workspace: "b")
      april_usage = usage_at(Time.utc(2026, 4, 20))
      april_invoice = bill_at(Time.utc(2026, 5, 1, 1))

      send_event(4, at: Time.utc(2026, 5, 10), region: "eu", workspace: "a")
      june_usage = usage_at(Time.utc(2026, 6, 1, 0, 30))

      {march_invoice:, april_usage:, april_invoice:, june_usage:, may_invoice: bill_at(Time.utc(2026, 6, 1, 1))}
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with charge filters and pricing group keys" do
    it_behaves_like "a recurring sum with filters and groups"

    context "with the ClickHouse store", clickhouse: true do
      let(:clickhouse_events_store) { true }

      it_behaves_like "a recurring sum with filters and groups"
    end
  end

  describe "with a terminated subscription" do
    let(:billed) do
      {
        march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
        april_invoice: [{amount_cents: 2800, units: 28, events_count: 6}],
        termination_invoice: [{amount_cents: 3200, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: Date.new(2026, 3, 31), units: 15, events_count: 3},
        {to: Date.new(2026, 4, 30), units: 28, events_count: 6},
        {to: Date.new(2026, 5, 15), units: 32, events_count: 7}
      ]
    end
    let(:usage_reads) { [] }

    def bill
      start_subscription
      send_sum_events
      march_invoice = bill_at(march_billed_at)

      send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20))
      send_event(5, at: Time.utc(2026, 4, 15))
      april_invoice = bill_at(Time.utc(2026, 5, 1, 1))

      send_event(4, at: Time.utc(2026, 5, 10))
      termination_invoice = travel_to(Time.utc(2026, 5, 15, 12)) do
        terminate_subscription(subscription)
        last_invoice_fees
      end

      {march_invoice:, april_invoice:, termination_invoice:}
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with a plan upgrade" do
    let(:upgraded_plan) { create(:plan, organization:, amount_cents: 1000, interval: "monthly") }
    let(:upgraded_charge) { create(:standard_charge, plan: upgraded_plan, billable_metric:, properties: {amount: "2"}) }
    let(:billed) do
      {
        march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
        # The recurring charge carries over to the new plan, which bills it at $2
        upgrade_invoice: [],
        april_usage: {amount_cents: 5600, units: 28, events_count: 6},
        april_invoice: [{amount_cents: 5600, units: 28, events_count: 6}],
        may_invoice: [{amount_cents: 6400, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {subscription_id: customer.subscriptions.order(:created_at).first.id, to: Date.new(2026, 3, 31), units: 15, events_count: 3},
        {charge_id: upgraded_charge.id, to: Date.new(2026, 4, 30), units: 28, events_count: 6},
        {charge_id: upgraded_charge.id, to: Date.new(2026, 5, 31), units: 32, events_count: 7}
      ]
    end
    let(:usage_reads) { [march_snapshot] }

    def bill
      start_subscription
      travel_to(Time.utc(2026, 3, 1)) { upgraded_charge }
      send_sum_events
      march_invoice = bill_at(march_billed_at)

      send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20))
      upgrade_invoice = travel_to(Time.utc(2026, 4, 15, 12)) do
        create_subscription({external_customer_id: customer.external_id, external_id: customer.external_id, plan_code: upgraded_plan.code})
        last_invoice_fees
      end

      # The upgraded subscription has no snapshot yet: it starts from the March one of the previous subscription
      send_event(5, at: Time.utc(2026, 4, 20))
      april_usage = usage_at(Time.utc(2026, 4, 25))
      april_invoice = bill_at(Time.utc(2026, 5, 1, 1))

      send_event(4, at: Time.utc(2026, 5, 10))
      {march_invoice:, upgrade_invoice:, april_usage:, april_invoice:, may_invoice: bill_at(Time.utc(2026, 6, 1, 1))}
    end

    include_examples "bills the same with every snapshot flag"
  end
end
