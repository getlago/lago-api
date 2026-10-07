# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Contract usage billing QA regressions" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
  let(:started_at) { Time.zone.parse("2026-10-06 00:00:00") }
  let(:boundary) { started_at + 1.month }
  let(:contract) do
    create(:contract, organization:, customer:, started_at:, billing_time: :anniversary,
      billing_entity: customer.billing_entity)
  end
  let(:aggregation_type) { :sum_agg }
  let(:recurring) { true }
  let(:field_name) { "units" }
  let(:billable_metric) do
    create(:billable_metric, organization:, aggregation_type:, recurring:, field_name:,
      weighted_interval: (aggregation_type == :weighted_sum_agg) ? :seconds : nil)
  end
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:timing) { :advance }
  let(:proration) { false }
  let(:display) { true }
  let(:regroup) { nil }
  let(:product_filter) { nil }
  let(:rate_card) do
    create(:rate_card, organization:, product:, product_filter:, currency: "USD", billing_timing: timing,
      proration:, display_on_invoice: display, regroup_paid_fees: regroup)
  end
  let(:rate_model) { :standard }
  let(:rate_properties) { {"amount" => "1"} }
  let(:rate) do
    RateCardRates::CreateService.call!(rate_card:, params: {
      code: "qa-rate", effective_from: started_at, rate_model:, rate_properties:,
      billing_interval_unit: :month, billing_interval_count: 1
    }).rate_card_rate
  end
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: started_at.to_date, billing_anchor_date: started_at.to_date,
      next_billing_at: (timing == :advance) ? started_at : boundary)
  end

  around do |example|
    travel_to(started_at + 12.hours) { example.run }
  end

  before do
    rate
    card
  end

  describe "BIL-765 and BIL-764 advance event invoices" do
    subject(:event_fees) do
      inputs.each_with_index do |input, index|
        event_at = input.fetch(:at, started_at + (index + 1).hours)
        travel_to(input.fetch(:received_at, event_at))
        create_event({external_contract_id: contract.external_id, code: billable_metric.code,
          timestamp: event_at.to_i, properties: input.fetch(:properties, {}).merge(field_name => input.fetch(:value))}, perform_jobs: false)
        perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      end
      Fee.where(contract:, fee_type: :product).order(:created_at).to_a
    end

    let(:inputs) { [3, 7, -3, 4].map { |value| {value: value.to_s} } }

    context "when the rebound stays below the billed maximum" do
      let(:inputs) { [3, 7, -3, 2, 2].map { |value| {value: value.to_s} } }

      it "charges nothing until usage exceeds ten" do
        expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 0, 100])
      end
    end

    context "when checking usage after a decrease" do
      let(:inputs) { [3, 7, -3].map { |value| {value: value.to_s} } }

      it "reports current usage separately from the billed maximum" do
        event_fees
        event = Event.where(organization:, external_subscription_id: contract.external_id).order(:timestamp).last
        selection = Events::PayInAdvanceMeteredItemsResolver.call!(event:).selections.sole
        item = selection.metered_item
        usage = BillableMetrics::AggregationFactory.new_instance(
          metered_item: item, billing_context: selection.billing_context,
          boundaries: item.aggregation_boundaries, current_usage: true
        ).aggregate(options: {is_current_usage: true, is_pay_in_advance: true})

        expect(usage).to have_attributes(current_usage_units: 7, aggregation: 10)
      end
    end

    context "when usage is grouped" do
      let(:rate_properties) { {"amount" => "1", "pricing_group_keys" => ["region"]} }
      let(:inputs) do
        [[3, "eu"], [7, "eu"], [-3, "eu"], [4, "us"], [4, "eu"]].map do |value, region|
          {value: value.to_s, properties: {"region" => region}}
        end
      end

      it "keeps the current usage and maximum separate for each group" do
        expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 400, 100])
      end
    end

    context "when another contract card prices the same metric" do
      let(:other_product) { create(:product, organization:, billable_metric:) }
      let(:other_rate_card) { create(:rate_card, organization:, product: other_product, currency: "USD", billing_timing: timing) }
      let(:other_rate) do
        RateCardRates::CreateService.call!(rate_card: other_rate_card, params: {
          code: "other-rate", effective_from: started_at, rate_model:, rate_properties:,
          billing_interval_unit: :month, billing_interval_count: 1
        }).rate_card_rate
      end
      let!(:other_card) do
        create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card,
          effective_date: started_at.to_date, billing_anchor_date: started_at.to_date, next_billing_at: started_at)
      end

      before { other_rate }

      it "bills each attachment independently" do
        fees_by_card = event_fees.group_by(&:contract_rate_card_id).transform_values { |fees| fees.map(&:amount_cents) }

        expect(fees_by_card).to eq(card.id => [300, 700, 0, 100], other_card.id => [300, 700, 0, 100])
      end
    end

    context "with a product filter" do
      let(:product_filter) { create(:product_filter, organization:, product:) }
      let(:metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
      let(:inputs) do
        [[3, "eu"], [100, "us"], [7, "eu"], [-3, "eu"], [4, "eu"]].map do |value, region|
          {value: value.to_s, properties: {"region" => region}}
        end
      end

      before do
        create(:product_filter_value, organization:, product_filter:, billable_metric_filter: metric_filter, value: "eu")
      end

      it "keeps unmatched events out of both pricing and persisted state" do
        expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 100])
        expect(CachedAggregation.where(contract_rate_card: card).order(:created_at).pluck(:current_aggregation))
          .to eq([3, 10, 7, 11])
      end
    end

    it "O10 bills only the newly reached unit" do
      event_fees
      expect(CachedAggregation.where(contract_rate_card: card).order(:created_at).pluck(:current_aggregation, :max_aggregation))
        .to eq([[3, 3], [10, 10], [7, 10], [11, 11]])
      expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 100])
      expect(event_fees.map { |fee| fee.invoice.status }).to eq(["finalized"] * 4)
    end

    context "with graduated pricing G10" do
      let(:rate_model) { :graduated }
      let(:rate_properties) do
        {"graduated_ranges" => [
          {"to_value" => "10", "per_unit_amount" => "1", "flat_amount" => "0"},
          {"to_value" => nil, "per_unit_amount" => "0.5", "flat_amount" => "0"}
        ]}
      end

      it "bills only unit eleven" do
        expect(event_fees.map(&:amount_cents)).to eq([300, 700, 0, 50])
      end
    end

    context "with percentage pricing M10" do
      let(:inputs) { [300, 700, -300, 400].map { |value| {value: value.to_s} } }
      let(:rate_model) { :percentage }
      let(:rate_properties) { {"rate" => "2.5", "fixed_amount" => "0.30"} }

      it "bills only the newly reached hundred units plus the event fee" do
        expect(event_fees.map(&:amount_cents)).to eq([780, 1780, 0, 280])
        expect(event_fees.third.amount_details).to include("fixed_fee_total_amount" => "0.0", "paid_events" => "0.0")
      end
    end

    context "with graduated percentage pricing I10" do
      let(:inputs) { [300, 700, -300, 400].map { |value| {value: value.to_s} } }
      let(:rate_model) { :graduated_percentage }
      let(:rate_properties) do
        {"graduated_percentage_ranges" => [
          {"to_value" => "1000", "rate" => "2", "flat_amount" => "0"},
          {"to_value" => nil, "rate" => "1", "flat_amount" => "5"}
        ]}
      end

      it "bills only the new tier exposure and flat fee" do
        expect(event_fees.map(&:amount_cents)).to eq([600, 1400, 0, 600])
      end
    end

    context "with prorated standard pricing O11" do
      let(:proration) { true }
      let(:rate_properties) { {"amount" => "10"} }
      let(:inputs) do
        [[0, 3], [1, 7], [10, -3], [14, 4]].map do |days, value|
          {at: started_at + days.days + 1.hour, value: value.to_s}
        end
      end

      it "prorates the one newly reached unit" do
        expect(event_fees.map(&:amount_cents)).to eq([3000, 6774, 0, 548])
      end
    end

    context "with nonrecurring unique package pricing K4" do
      let(:aggregation_type) { :unique_count_agg }
      let(:recurring) { false }
      let(:field_name) { "user_id" }
      let(:rate_model) { :package }
      let(:rate_properties) { {"amount" => "5", "package_size" => 2, "free_units" => 0} }
      let(:inputs) { %w[A A B].map { |value| {value:} } }

      it "bills one package for A, A, B" do
        expect(event_fees.map(&:amount_cents)).to eq([500, 0, 0])
      end

      context "with ClickHouse-backed event aggregation", clickhouse: true do
        subject(:event_fees) do
          Events::Stores::StoreFactory.with_override(store_class: Events::Stores::ClickhouseStore, deduplicate: false) do
            inputs.each_with_index do |input, index|
              travel_to(started_at + (index + 1).hours)
              attributes = {
                organization_id: organization.id, external_subscription_id: contract.external_id,
                code: billable_metric.code, transaction_id: "qa-#{index}", timestamp: Time.current,
                properties: {field_name => input.fetch(:value)}
              }
              Clickhouse::EventsEnriched.create!(**attributes, value: input.fetch(:value), enriched_at: Time.current)
              Events::PayInAdvanceService.call!(event: Events::Common.new(**attributes))
              perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
            end
          end
          Fee.where(contract:, fee_type: :product).order(:created_at).to_a
        end

        let(:organization) do
          create(:organization, feature_flags: ["product_catalog"], webhook_url: nil, clickhouse_events_store: true)
        end

        it "bills one package for A, A, B" do
          expect(event_fees.map(&:amount_cents)).to eq([500, 0, 0])
        end
      end
    end
  end

  describe "BIL-756 BM9 recurring weighted SUM" do
    subject(:billing_result) { Contracts::BillService.call!(contracts: [contract], timestamp: boundary) }

    let(:started_at) { Time.zone.parse("2026-10-02 00:00:00") }
    let(:timing) { :arrears }
    let(:aggregation_type) { :weighted_sum_agg }
    let(:field_name) { "gb" }
    let(:event) do
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: started_at, properties: {"gb" => "10"})
    end

    before { event }

    it "bills ten weighted units without a subscription context" do
      expect(billing_result.invoices.sole.fees.sole).to have_attributes(units: 10, amount_cents: 1000)
    end

    it "carries ten units into an eventless second period" do
      billing_result
      second_period = Contracts::BillService.call!(contracts: [contract], timestamp: boundary + 1.month)

      expect(second_period.invoices.sole.fees.sole).to have_attributes(units: 10, amount_cents: 1000)
    end

    context "when several periods are billed together" do
      subject(:billing_result) { Contracts::BillService.call!(contracts: [contract], timestamp: boundary + 2.months) }

      it "carries the opening balance through each eventless period" do
        expect(billing_result.invoices.flat_map(&:fees).map { |fee| [fee.units, fee.amount_cents] })
          .to eq([[10, 1000], [10, 1000], [10, 1000]])
      end

      context "with grouped usage" do
        let(:rate_properties) { {"amount" => "1", "pricing_group_keys" => ["region"]} }
        let(:event) do
          create(:event, organization:, customer:, external_subscription_id: contract.external_id,
            code: billable_metric.code, timestamp: started_at, properties: {"gb" => "10", "region" => "eu"})
        end

        it "uses only the latest closing balance for each group" do
          expect(billing_result.invoices.flat_map(&:fees).map { |fee| [fee.units, fee.amount_cents, fee.grouped_by] })
            .to eq([[10, 1000, {"region" => "eu"}]] * 3)
        end
      end
    end

    context "when billing runs naturally on a three-day cadence" do
      subject(:natural_invoice) do
        BillingSegments::ScheduleJob.perform_now(customer.id)
        BillingSegments::ProcessJob.perform_now(customer.id)
        Invoice.where(customer:).sole
      end

      let(:boundary) { started_at + 3.days }
      let(:rate) do
        RateCardRates::CreateService.call!(rate_card:, params: {
          code: "qa-rate", effective_from: started_at, rate_model:, rate_properties:,
          billing_interval_unit: :day, billing_interval_count: 3
        }).rate_card_rate
      end

      before { travel_to(boundary + 1.hour) }

      it "creates the first invoice after scheduling advances the cursor" do
        expect(natural_invoice.fees.sole).to have_attributes(units: 10, amount_cents: 1000)
      end
    end
  end

  describe "BIL-768 TM4 paid fee reconciliation" do
    subject(:billing_result) { Contracts::BillService.call!(contracts: [contract], timestamp: boundary) }

    let(:recurring) { false }
    let(:display) { false }
    let(:regroup) { :invoice }
    let(:segment_status) { :pending }
    let(:segment) do
      create(:billing_segment, organization:, customer:, contract:, contract_rate_card: card,
        rate_card_rate: rate, rate_override: nil, currency: "USD", rate_properties:,
        started_at:, ended_at: BillingSegment.inclusive_end(boundary), cycle_started_at: started_at,
        billing_at: started_at, status: segment_status)
    end
    let(:metered_item) { Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: segment) }
    let!(:fees) do
      [300, 700, 100, 100, 100].each_with_index.map do |amount_cents, index|
        create(:fee, organization:, invoice: nil, subscription: nil, contract:, contract_rate_card: card,
          invoiceable: product, rate_card_rate: rate, fee_type: :product, billing_entity: customer.billing_entity,
          amount_cents:, precise_amount_cents: amount_cents, amount_currency: "USD", taxes_amount_cents: 0,
          payment_status: (index < 3) ? :succeeded : :pending, succeeded_at: (index < 3) ? started_at + 1.hour : nil,
          pay_in_advance: true, properties: metered_item.filtered_for_charge_boundaries)
      end
    end

    it "honors a future manual billing cutoff" do
      expect(billing_result.invoices.map(&:total_amount_cents)).to eq([1100])
    end

    context "when the wall clock reaches the boundary" do
      before { travel_to(boundary) }

      it "regroups only the three paid fees and is idempotent" do
        invoice = billing_result.invoices.sole.reload
        expect(invoice).to have_attributes(total_amount_cents: 1100, payment_status: "succeeded", status: "finalized")
        expect(invoice.fees.pluck(:id)).to match_array(fees.first(3).map(&:id))
        expect(Contracts::BillService.call!(contracts: [contract], timestamp: boundary).invoices).to eq([])
      end

      context "when the scheduled jobs perform billing" do
        subject(:scheduled_invoice) do
          BillingSegments::ScheduleJob.perform_now(customer.id)
          BillingSegments::ProcessJob.perform_now(customer.id)
          Invoice.where(customer:).sole
        end

        it "regroups only paid fees" do
          expect(scheduled_invoice).to have_attributes(total_amount_cents: 1100, payment_status: "succeeded", status: "finalized")
          expect(scheduled_invoice.fees.pluck(:id)).to match_array(fees.first(3).map(&:id))
        end
      end
    end
  end
end
