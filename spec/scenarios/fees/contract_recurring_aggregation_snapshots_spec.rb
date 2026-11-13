# frozen_string_literal: true

require "rails_helper"

describe "Contract recurring aggregation snapshots", :premium, transaction: false do
  let(:organization) do
    create(:organization, webhook_url: nil, clickhouse_events_store:, feature_flags: ["product_catalog", *snapshot_flags])
  end
  let(:snapshot_flags) { [] }
  let(:clickhouse_events_store) { false }
  let(:product_events_topic) { nil }
  let(:customer) { organization.customers.find_by!(external_id: "snapshot-customer") }
  let(:contract) { organization.contracts.order(:created_at).last }
  let(:started_at) { Time.utc(2026, 3, 1) }
  let(:aggregation_type) { "sum_agg" }
  let(:metric_params) do
    {name: "Storage", code: "storage", aggregation_type:, field_name: "amount", recurring: true, weighted_interval:}.compact
  end
  let(:weighted_interval) { nil }
  let(:billing_timing) { "arrears" }
  let(:proration) { false }
  let(:rates) { [{code: "base", effective_from: started_at, amount: "1"}] }
  let(:read_periods) { {usage: [], invoice: []} }
  let(:march_billed_at) { Time.utc(2026, 4, 1, 1) }
  let(:march_watermark) { march_billed_at - RecurringAggregationSnapshot::WATERMARK_LAG }
  let(:march_snapshot) { BillingSegment.inclusive_end(Time.utc(2026, 4, 1)) }
  let(:april_snapshot) { BillingSegment.inclusive_end(Time.utc(2026, 5, 1)) }
  # One read per segment, nil when it falls back to the full history
  let(:invoice_reads) { [nil, march_snapshot, april_snapshot] }
  let(:usage_reads) { [march_snapshot, april_snapshot] }

  around do |example|
    topic = ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"]
    ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = product_events_topic
    example.run
  ensure
    ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = topic
  end

  before do
    allow(RecurringAggregationSnapshots::FetchService).to receive(:call!).and_wrap_original do |method, **args|
      method.call(**args).tap { read_periods[:invoice] << it.period&.to_datetime }
    end
  end

  def create_rate_card(code:, filter_code: nil, rates: self.rates)
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: code, code:, product_code: "storage", product_filter_code: filter_code, currency: "USD",
        billing_timing:, proration:,
        rates: rates.map do |rate|
          {
            code: "#{code}-#{rate[:code]}", effective_from: rate[:effective_from].iso8601, rate_model: "standard",
            billing_interval_unit: "month", rate_properties: {amount: rate[:amount]}
          }
        end
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans/snapshot-plan/applied_rate_cards", {applied_rate_card: {rate_card_code: code, units: 1}})
    end
  end

  def create_catalog
    create_metric(metric_params)
    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Storage", code: "storage", product_type: "metered", billable_metric_code: "storage"
      }})
    end
    create_product_filters
    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Snapshot plan", code: "snapshot-plan", currency: "USD"}})
    end
    create_rate_cards
  end

  def create_product_filters
  end

  def create_rate_cards
    create_rate_card(code: "storage")
  end

  def start_contract
    travel_to(started_at - 1.day) do
      create_or_update_customer({external_id: "snapshot-customer", timezone: "UTC", currency: "USD"})
      create_catalog
    end

    travel_to(started_at + 5.minutes) do
      api_call do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "snapshot-contract", external_customer_id: "snapshot-customer",
          plan_code: "snapshot-plan", started_at: started_at.iso8601
        }})
      end
    end
  end

  def send_event(amount, at:, timestamp: at, **properties)
    travel_to(at) do
      params = {code: "storage", external_contract_id: "snapshot-contract", timestamp: timestamp.to_i, properties: {amount:, **properties}}

      if organization.clickhouse_events_store?
        attributes = {
          organization_id: organization.id, code: "storage", transaction_id: SecureRandom.uuid, timestamp:,
          properties: params[:properties], value: amount.to_s, decimal_value: amount.to_d, enriched_at: Time.current
        }

        if organization.product_events_pipeline?
          Clickhouse::ProductEventsEnriched.create!(**attributes, external_contract_id: "snapshot-contract")
        else
          Clickhouse::EventsEnriched.create!(**attributes, external_subscription_id: "snapshot-contract")
        end
      else
        create_event(params)
      end
    end
  end

  def bill_at(time)
    travel_to(time) do
      clock_job { Clock::ProcessBillingOperationsJob.perform_later }
      product_fees(customer.invoices.where(created_at: Time.current).sole)
    end
  end

  def usage_at(time)
    invoice_reads = read_periods[:invoice].size
    usage = travel_to(time) do
      api_call(perform_jobs: false) { get_with_token(organization, "/api/v2/contracts/snapshot-contract/current_usage") }
    end
    read_periods[:usage].concat(read_periods[:invoice].slice!(invoice_reads..))

    usage[:current_usage][:rate_cards].map do |card|
      {
        filter: card[:product_filter_code],
        amount_cents: card[:amount_cents],
        units: round_units(BigDecimal(card[:units])),
        events_count: card[:events_count]
      }.compact
    end.sort_by(&:to_s)
  end

  # The stores compute weighted sums with different decimal precisions
  def round_units(units)
    units.round(10)
  end

  def product_fees(invoice)
    invoice.fees.where(fee_type: :product).includes(:product_filter).map do |fee|
      {
        filter: fee.product_filter&.code,
        amount_cents: fee.amount_cents,
        units: round_units(fee.units),
        events_count: fee.events_count
      }.compact
    end.sort_by(&:to_s)
  end

  def written_snapshots
    ContractRecurringAggregationSnapshot.where(organization:).includes(:product_filter).map do |snapshot|
      {
        contract_id: snapshot.contract_id,
        product: snapshot.product.code,
        to: snapshot.to_datetime,
        filter: snapshot.product_filter&.code,
        priced_filters: ProductFilter.where(id: snapshot.priced_product_filter_ids).pluck(:code).presence,
        units: snapshot.units,
        events_count: snapshot.events_count
      }.compact
    end
  end

  def expected_snapshots
    contract_id = contract.id
    snapshots.map { {contract_id:, product: "storage"}.merge(it) }
  end

  # The event ingested at the watermark of the March invoice is in the March snapshot, so a delta reading
  # it too counts it twice. The one ingested after is billed in March but left to the delta.
  def send_march_events
    send_event(10, at: Time.utc(2026, 3, 5))
    send_event(3, at: Time.utc(2026, 3, 10))
    send_event(2, at: march_watermark, timestamp: Time.utc(2026, 3, 31, 12))
    send_event(1, at: march_watermark + 2.minutes, timestamp: Time.utc(2026, 3, 31, 18))
  end

  # Three billed periods: March writes the first snapshot, April and May read from the previous one
  def bill
    start_contract
    send_march_events
    march_invoice = bill_at(march_billed_at)

    # Dated in March, ingested after the March invoice
    send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20))
    send_event(5, at: Time.utc(2026, 4, 15))
    april_usage = usage_at(Time.utc(2026, 4, 20))
    april_invoice = bill_at(Time.utc(2026, 5, 1, 1))

    send_event(4, at: Time.utc(2026, 5, 10))
    # May is not billed yet: the usage of June starts from the April snapshot
    june_usage = usage_at(Time.utc(2026, 6, 1, 0, 0, 30))

    {march_invoice:, april_usage:, april_invoice:, june_usage:, may_invoice: bill_at(Time.utc(2026, 6, 1, 1))}
  end

  shared_examples "on each ClickHouse pipeline" do |examples|
    context "with the ClickHouse store", clickhouse: true do
      let(:clickhouse_events_store) { true }

      it_behaves_like examples

      context "with the product events pipeline" do
        let(:product_events_topic) { "product_events_raw" }

        it_behaves_like examples
      end
    end
  end

  shared_examples "bills the same with every snapshot flag" do
    context "with both flags off" do
      it "bills from the full history" do
        expect(bill.slice(*billed.keys)).to eq(billed)
        expect(written_snapshots).to be_empty
        expect(read_periods).to eq(usage: [], invoice: [])
      end
    end

    context "with snapshot writes only" do
      let(:snapshot_flags) { %w[recurring_aggregation_snapshots] }

      it "writes the snapshots and bills from the full history" do
        expect(bill.slice(*billed.keys)).to eq(billed)
        expect(written_snapshots).to match_array(expected_snapshots)
        expect(read_periods).to eq(usage: [], invoice: [])
      end
    end

    context "with snapshot writes and reads" do
      let(:snapshot_flags) { %w[recurring_aggregation_snapshots persisted_recurring_values] }

      it "bills what the full history bills, starting from the snapshots" do
        expect(bill.slice(*billed.keys)).to eq(billed)
        expect(written_snapshots).to match_array(expected_snapshots)
        expect(read_periods).to eq(invoice: invoice_reads, usage: usage_reads)
      end
    end

    context "with snapshot reads only" do
      let(:snapshot_flags) { %w[persisted_recurring_values] }

      it "finds no snapshot and bills from the full history" do
        expect(bill.slice(*billed.keys)).to eq(billed)
        expect(written_snapshots).to be_empty
        expect(read_periods.values.flatten.uniq).to eq([nil])
      end
    end
  end

  shared_examples "an in-arrears recurring sum" do
    let(:billed) do
      {
        # 10 + 3 + 2 + 1
        march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
        # 16 + 7 + 5
        april_usage: [{amount_cents: 2800, units: 28, events_count: 6}],
        april_invoice: [{amount_cents: 2800, units: 28, events_count: 6}],
        # 28 + 4
        june_usage: [{amount_cents: 3200, units: 32, events_count: 7}],
        may_invoice: [{amount_cents: 3200, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        # 10 + 3 + 2: the event ingested after the watermark is left to the delta
        {to: march_snapshot, units: 15, events_count: 3},
        {to: april_snapshot, units: 28, events_count: 6},
        {to: BillingSegment.inclusive_end(Time.utc(2026, 6, 1)), units: 32, events_count: 7}
      ]
    end

    include_examples "bills the same with every snapshot flag"

    context "with a snapshot edited after it was written" do
      let(:snapshot_flags) { %w[recurring_aggregation_snapshots persisted_recurring_values] }

      # A read that ignores the stored values bills the full history, as every other example expects
      def bill_at(time)
        super.tap do
          ContractRecurringAggregationSnapshot.where(organization:).sole.update!(units: 115, events_count: 4) if time == march_billed_at
        end
      end

      # 115 + 1 after the watermark + 7 + 5, then + 4 in May
      it "adds the stored values to the delta" do
        expect(bill).to eq(
          march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
          april_usage: [{amount_cents: 12800, units: 128, events_count: 7}],
          april_invoice: [{amount_cents: 12800, units: 128, events_count: 7}],
          june_usage: [{amount_cents: 13200, units: 132, events_count: 8}],
          may_invoice: [{amount_cents: 13200, units: 132, events_count: 8}]
        )
      end
    end
  end

  describe "with an in-arrears recurring sum" do
    it_behaves_like "an in-arrears recurring sum"

    include_examples "on each ClickHouse pipeline", "an in-arrears recurring sum"
  end

  shared_examples "a prorated recurring sum" do
    let(:proration) { true }
    let(:billed) do
      {
        # Each event prorated over the days left in its period, earlier units carried in full
        # (10 × 27 + 3 × 22 + 2 × 1 + 1 × 1) / 31 = 10.94
        march_invoice: [{amount_cents: 1094, units: 16, events_count: 4}],
        # 16 + 7 + 5 × 16 / 30 = 25.67
        april_usage: [{amount_cents: 2567, units: 28, events_count: 6}],
        april_invoice: [{amount_cents: 2567, units: 28, events_count: 6}],
        june_usage: [{amount_cents: 3200, units: 32, events_count: 7}],
        # 28 + 4 × 22 / 31 = 30.84
        may_invoice: [{amount_cents: 3084, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: march_snapshot, units: 15, events_count: 3},
        {to: april_snapshot, units: 28, events_count: 6},
        {to: BillingSegment.inclusive_end(Time.utc(2026, 6, 1)), units: 32, events_count: 7}
      ]
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with a prorated recurring sum" do
    it_behaves_like "a prorated recurring sum"

    include_examples "on each ClickHouse pipeline", "a prorated recurring sum"
  end

  shared_examples "a recurring weighted sum" do
    let(:aggregation_type) { "weighted_sum_agg" }
    let(:weighted_interval) { "seconds" }
    let(:billed) do
      {
        # (10 × 5 + 13 × 21.5 + 15 × 0.25 + 16 × 0.25) / 31 days
        march_invoice: [{amount_cents: 1088, units: BigDecimal("10.8790322581"), events_count: 4}],
        # A weighted sum ignores events dated in a billed period: (16 × 14 + 21 × 16) / 30 days
        april_usage: [{amount_cents: 1867, units: BigDecimal("18.6666666667"), events_count: 1}],
        april_invoice: [{amount_cents: 1867, units: BigDecimal("18.6666666667"), events_count: 1}],
        # (21 × 9 + 25 × 22) / 31 days
        may_invoice: [{amount_cents: 2384, units: BigDecimal("23.8387096774"), events_count: 1}]
        # No June usage: after an unbilled period it misses that period's events with every flag
      }
    end
    let(:snapshots) do
      [
        {to: march_snapshot, units: 16, events_count: 0},
        {to: april_snapshot, units: 21, events_count: 0},
        {to: BillingSegment.inclusive_end(Time.utc(2026, 6, 1)), units: 25, events_count: 0}
      ]
    end

    include_examples "bills the same with every snapshot flag"

    context "with a snapshot edited after it was written" do
      let(:snapshot_flags) { %w[recurring_aggregation_snapshots persisted_recurring_values] }

      def bill_at(time)
        super.tap do
          ContractRecurringAggregationSnapshot.where(organization:).sole.update!(units: 116) if time == march_billed_at
        end
      end

      it "starts April from the stored value" do
        expect(bill.slice(*billed.keys)).to eq(
          march_invoice: [{amount_cents: 1088, units: BigDecimal("10.8790322581"), events_count: 4}],
          # (116 × 14 + 121 × 16) / 30 days
          april_usage: [{amount_cents: 11867, units: BigDecimal("118.6666666667"), events_count: 1}],
          april_invoice: [{amount_cents: 11867, units: BigDecimal("118.6666666667"), events_count: 1}],
          # (121 × 9 + 125 × 22) / 31 days
          may_invoice: [{amount_cents: 12384, units: BigDecimal("123.8387096774"), events_count: 1}]
        )
      end
    end
  end

  describe "with a recurring weighted sum" do
    it_behaves_like "a recurring weighted sum"

    include_examples "on each ClickHouse pipeline", "a recurring weighted sum"
  end

  describe "with a rate change inside a cycle" do
    let(:rates) do
      [
        {code: "base", effective_from: started_at, amount: "1"},
        {code: "raise", effective_from: Time.utc(2026, 4, 15), amount: "2"}
      ]
    end
    let(:mid_april_snapshot) { BillingSegment.inclusive_end(Time.utc(2026, 4, 15)) }
    let(:billed) do
      {
        march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
        # The first slice of April closes on the rate change: 16 + 7 + 5
        mid_april_invoice: [{amount_cents: 2800, units: 28, events_count: 6}],
        # The second slice starts from the first slice's snapshot: 28 + 4, at $2
        april_usage: [{amount_cents: 6400, units: 32, events_count: 7}],
        april_invoice: [{amount_cents: 6400, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: march_snapshot, units: 15, events_count: 3},
        {to: mid_april_snapshot, units: 28, events_count: 6},
        {to: april_snapshot, units: 32, events_count: 7}
      ]
    end
    let(:invoice_reads) { [nil, march_snapshot, mid_april_snapshot] }
    let(:usage_reads) { [mid_april_snapshot] }

    def bill
      start_contract
      send_march_events
      march_invoice = bill_at(march_billed_at)

      send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20))
      send_event(5, at: Time.utc(2026, 4, 10))
      mid_april_invoice = bill_at(Time.utc(2026, 4, 15, 1))

      send_event(4, at: Time.utc(2026, 4, 20))
      april_usage = usage_at(Time.utc(2026, 4, 25))

      {march_invoice:, mid_april_invoice:, april_usage:, april_invoice: bill_at(Time.utc(2026, 5, 1, 1))}
    end

    include_examples "bills the same with every snapshot flag"
  end

  shared_examples "a filtered and an unfiltered card on one product" do
    let(:metric_params) { super().merge(filters: [{key: "region", values: %w[eu us]}]) }
    let(:billed) do
      {
        # us: 3 + 1 at $1, eu: (10 + 2) × $2
        march_invoice: [
          {amount_cents: 400, units: 4, events_count: 2},
          {filter: "eu", amount_cents: 2400, units: 12, events_count: 2}
        ],
        # us: 4 + 7, eu: 12 + 5
        april_usage: [
          {amount_cents: 1100, units: 11, events_count: 3},
          {filter: "eu", amount_cents: 3400, units: 17, events_count: 3}
        ],
        april_invoice: [
          {amount_cents: 1100, units: 11, events_count: 3},
          {filter: "eu", amount_cents: 3400, units: 17, events_count: 3}
        ],
        # us: 11 + 4
        june_usage: [
          {amount_cents: 1500, units: 15, events_count: 4},
          {filter: "eu", amount_cents: 3400, units: 17, events_count: 3}
        ],
        may_invoice: [
          {amount_cents: 1500, units: 15, events_count: 4},
          {filter: "eu", amount_cents: 3400, units: 17, events_count: 3}
        ]
      }
    end
    let(:snapshots) do
      [
        # The us event ingested after the watermark is left to the delta
        {to: march_snapshot, filter: "eu", priced_filters: ["eu"], units: 12, events_count: 2},
        {to: march_snapshot, priced_filters: ["eu"], units: 3, events_count: 1},
        {to: april_snapshot, filter: "eu", units: 17, events_count: 3},
        {to: april_snapshot, units: 11, events_count: 3},
        {to: BillingSegment.inclusive_end(Time.utc(2026, 6, 1)), filter: "eu", units: 17, events_count: 3},
        {to: BillingSegment.inclusive_end(Time.utc(2026, 6, 1)), units: 15, events_count: 4}
      ]
    end
    # Both cards start with the contract, so only the March segment prices the EU filter
    # (BillingSegment#priced_product_filter_ids): April reads the March snapshots as stale.
    let(:invoice_reads) { [nil, nil, nil, nil, april_snapshot, april_snapshot] }
    let(:usage_reads) { [nil, nil, april_snapshot, april_snapshot] }

    def create_product_filters
      api_call do
        post_with_token(organization, "/api/v2/products/storage/filters", {filter: {
          name: "EU", code: "eu", values: [{key: "region", value: "eu"}]
        }})
      end
    end

    def create_rate_cards
      create_rate_card(code: "storage")
      create_rate_card(code: "storage-eu", filter_code: "eu", rates: [{code: "base", effective_from: started_at, amount: "2"}])
    end

    def bill
      start_contract
      send_event(10, at: Time.utc(2026, 3, 5), region: "eu")
      send_event(3, at: Time.utc(2026, 3, 10), region: "us")
      send_event(2, at: march_watermark, timestamp: Time.utc(2026, 3, 31, 12), region: "eu")
      send_event(1, at: march_watermark + 2.minutes, timestamp: Time.utc(2026, 3, 31, 18), region: "us")
      march_invoice = bill_at(march_billed_at)

      send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20), region: "us")
      send_event(5, at: Time.utc(2026, 4, 15), region: "eu")
      april_usage = usage_at(Time.utc(2026, 4, 20))
      april_invoice = bill_at(Time.utc(2026, 5, 1, 1))

      send_event(4, at: Time.utc(2026, 5, 10), region: "us")
      june_usage = usage_at(Time.utc(2026, 6, 1, 0, 0, 30))

      {march_invoice:, april_usage:, april_invoice:, june_usage:, may_invoice: bill_at(Time.utc(2026, 6, 1, 1))}
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with a filtered and an unfiltered card on one product" do
    it_behaves_like "a filtered and an unfiltered card on one product"

    include_examples "on each ClickHouse pipeline", "a filtered and an unfiltered card on one product"
  end

  describe "with a terminated contract" do
    let(:terminated_at) { Time.utc(2026, 5, 15, 12) }
    let(:billed) do
      {
        march_invoice: [{amount_cents: 1600, units: 16, events_count: 4}],
        april_invoice: [{amount_cents: 2800, units: 28, events_count: 6}],
        # 28 + 4, not prorated: the recurring units are billed in full
        termination_invoice: [{amount_cents: 3200, units: 32, events_count: 7}]
      }
    end
    let(:snapshots) do
      [
        {to: march_snapshot, units: 15, events_count: 3},
        {to: april_snapshot, units: 28, events_count: 6},
        {to: BillingSegment.inclusive_end(terminated_at), units: 32, events_count: 7}
      ]
    end
    let(:usage_reads) { [] }

    def bill
      start_contract
      send_march_events
      march_invoice = bill_at(march_billed_at)

      send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20))
      send_event(5, at: Time.utc(2026, 4, 15))
      april_invoice = bill_at(Time.utc(2026, 5, 1, 1))

      send_event(4, at: Time.utc(2026, 5, 10))
      termination_invoice = travel_to(terminated_at) do
        api_call { delete_with_token(organization, "/api/v2/contracts/snapshot-contract") }
        product_fees(customer.invoices.where(created_at: Time.current).sole)
      end

      {march_invoice:, april_invoice:, termination_invoice:}
    end

    include_examples "bills the same with every snapshot flag"
  end

  describe "with an advance recurring card" do
    let(:billing_timing) { "advance" }
    let(:billed) do
      {
        # Each renewal prices the units up to the start of its period
        april_renewal: [{amount_cents: 1600, units: 16, events_count: 4}],
        april_usage: [{amount_cents: 2800, units: 28, events_count: 6}],
        # 16 + 7 + 5
        may_renewal: [{amount_cents: 2800, units: 28, events_count: 6}],
        # Each event is paid on arrival, between the renewals
        event_fees: [[10, 1000], [3, 300], [2, 200], [1, 100], [16, 1600], [7, 700], [5, 500], [28, 2800]]
      }
    end
    let(:snapshots) { [] }
    # No arrears close writes a snapshot for an advance card: the six events and the renewals
    # of March (at the contract start), April and May all read the full history
    let(:invoice_reads) { Array.new(9) }
    let(:usage_reads) { [nil] }

    def bill
      start_contract
      send_march_events
      april_renewal = bill_at(march_billed_at)

      send_event(7, at: Time.utc(2026, 4, 2), timestamp: Time.utc(2026, 3, 20))
      send_event(5, at: Time.utc(2026, 4, 15))
      april_usage = usage_at(Time.utc(2026, 4, 20))

      {
        april_renewal:, april_usage:, may_renewal: bill_at(Time.utc(2026, 5, 1, 1)),
        event_fees: Fee.where(organization:, fee_type: :product).order(:created_at).pluck(:units, :amount_cents)
      }
    end

    include_examples "bills the same with every snapshot flag"
  end
end
