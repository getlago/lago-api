# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::BillingSegmentsResolver do
  subject(:filter_targets) { resolver.filter_targets }

  let(:resolver) { described_class.new(billing_segments: [billing_segment]) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:, external_id: "contract-id") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:rate_card) { create(:rate_card, organization:, product:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
  let(:billing_segment) do
    build(
      :billing_segment,
      organization:,
      customer:,
      contract:,
      contract_rate_card:,
      rate_card_rate:,
      cycle_started_at: Time.zone.parse("2026-09-01"),
      started_at: Time.zone.parse("2026-09-01"),
      ended_at: Time.zone.parse("2026-09-30 23:59:59")
    )
  end

  describe "#filter_targets" do
    let(:event) do
      create(
        :event,
        organization:,
        customer:,
        external_subscription_id: contract.external_id,
        code: billable_metric.code,
        timestamp: billing_segment.started_at + 1.day
      )
    end

    context "with unsaved segment objects" do
      before do
        event
      end

      it "returns targets without persisting supplied slices" do
        legacy_segment_count = LegacyBillingSegment.count
        targets = described_class.new(billing_segments: [billing_segment]).filter_targets

        expect(targets).to eq(billing_segment.target_key => {nil => event.created_at})
        expect(billing_segment).not_to respond_to(:persisted?)
        expect(LegacyBillingSegment.count).to eq(legacy_segment_count)
      end

      it "applies explicit code filtering to unsaved targets" do
        expect(described_class.new(billing_segments: [billing_segment], codes: ["unknown_code"]).filter_targets).to eq({})
      end
    end

    it "rejects ids because billing periods are supplied as in-memory slices" do
      expect { described_class.new(billing_segments: ["legacy-segment-id"]).filter_targets }
        .to raise_error(ArgumentError, "billing_segments must contain in-memory BillingSegment objects")
    end

    context "when selecting by captured metric code" do
      let(:captured_code) { "metric_code" }
      let(:captured_code_segment) { BillingSegment.new(billable_metric_code: captured_code) }
      let(:resolver) { described_class.new(billing_segments: [captured_code_segment], codes: ["metric_code"]) }
      let(:selected_segments) { resolver.send(:target_segments) }

      it "selects segments without querying or traversing associations" do
        queries = []
        subscriber = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

        selected = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          selected_segments
        end

        expect(selected).to eq([captured_code_segment])
        expect(queries).to be_empty
      end

      context "when the captured code differs" do
        let(:captured_code) { "other" }

        it "excludes the segment" do
          expect(selected_segments).to eq([])
        end
      end

      context "when the captured code is nil" do
        let(:captured_code) { nil }

        it "excludes the segment" do
          expect(selected_segments).to eq([])
        end
      end
    end

    it "memoizes the filter target for a billing segment instance" do
      create(
        :event,
        organization:,
        customer:,
        external_subscription_id: contract.external_id,
        code: billable_metric.code,
        timestamp: billing_segment.started_at + 1.day
      )
      allow(Events::BillingPeriodFilters::FilterTarget).to receive(:from_billing_segment).and_call_original

      filter_targets

      expect(Events::BillingPeriodFilters::FilterTarget).to have_received(:from_billing_segment).once
    end

    context "when matching a product filter priced by a rate card" do
      let(:priced_filter) { create(:product_filter, organization:, product:) }
      let(:specific_filter) { create(:product_filter, organization:, product:) }
      let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us]) }
      let(:event) do
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, properties: {"region" => "us"}, timestamp: billing_segment.started_at + 1.hour)
      end
      let(:target_filter) { Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment:) }
      let(:matching) { Events::BillingPeriodFilters::EventMatchingService.call(target_filter:, event:) }
      let(:priced_rate_card) { create(:rate_card, organization:, product:, product_filter: priced_filter) }

      before do
        create(:product_filter_value, organization:, product_filter: priced_filter, billable_metric_filter: region_filter, value: "eu")
        create(:product_filter_value, organization:, product_filter: priced_filter, billable_metric_filter: region_filter, value: "us")
        create(:product_filter_value, organization:, product_filter: specific_filter, billable_metric_filter: region_filter, value: "us")
        contract_rate_card.update!(rate_card: priced_rate_card, effective_date: effective_date)
      end

      context "when the applied card is effective before the segment" do
        let(:effective_date) { Date.new(2026, 8, 31) }

        it "does not give the out-of-window card pricing precedence" do
          expect(matching.filter).to eq(specific_filter)
        end
      end

      context "when the applied card is effective after the segment" do
        let(:effective_date) { Date.new(2026, 10, 1) }

        it "does not give the out-of-window card pricing precedence" do
          expect(matching.filter).to eq(specific_filter)
        end
      end
    end

    context "with overlapping product filters" do
      let(:filter_key) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[25 50 75]) }
      let(:kind_key) { create(:billable_metric_filter, organization:, billable_metric:, key: "kind", values: ["x"]) }
      let(:broad_filter) { create(:product_filter, organization:, product:, created_at: 3.days.ago) }
      let(:precise_filter) { create(:product_filter, organization:, product:, created_at: 2.days.ago) }
      let(:other_filter) { create(:product_filter, organization:, product:, created_at: 1.day.ago) }

      let(:event_25) { create_event("25", nil, at: billing_segment.started_at + 1.hour) }
      let(:event_50) { create_event("50", "x", at: billing_segment.started_at + 2.hours) }
      let(:event_75) { create_event("75", nil, at: billing_segment.started_at + 3.hours) }

      before do
        create(:product_filter_value, organization:, product_filter: broad_filter, billable_metric_filter: filter_key, value: "50")
        create(:product_filter_value, organization:, product_filter: broad_filter, billable_metric_filter: filter_key, value: "25")
        create(:product_filter_value, organization:, product_filter: precise_filter, billable_metric_filter: filter_key, value: "50")
        create(:product_filter_value, organization:, product_filter: precise_filter, billable_metric_filter: kind_key, value: "x")
        create(:product_filter_value, organization:, product_filter: other_filter, billable_metric_filter: filter_key, value: "50")
        create(:product_filter_value, organization:, product_filter: other_filter, billable_metric_filter: kind_key, value: "x")
      end

      def create_event(region, kind, at:)
        properties = {"region" => region}
        properties["kind"] = kind if kind
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, properties:, timestamp: at)
      end

      it "reports every matching filter and the default bucket" do
        event_25
        event_50
        event_75
        routed = filter_targets[billing_segment.target_key]

        expect(routed.keys).to match_array([broad_filter.id, precise_filter.id, other_filter.id, nil])
        expect(routed).to eq(
          broad_filter.id => event_50.created_at,
          precise_filter.id => event_50.created_at,
          other_filter.id => event_50.created_at,
          nil => event_75.created_at
        )
      end
    end

    context "with unsaved segments from contracts sharing a metric code" do
      let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us]) }
      let(:eu_filter) { create(:product_filter, organization:, product:) }
      let(:second_contract) { create(:contract, organization:, customer:, external_id: "second-contract-id") }
      let(:second_card) { create(:contract_rate_card, organization:, contract: second_contract, rate_card:) }
      let(:second_segment) do
        build(:billing_segment, organization:, customer:, contract: second_contract, contract_rate_card: second_card,
          rate_card_rate:, cycle_started_at: billing_segment.cycle_started_at,
          started_at: billing_segment.started_at, ended_at: billing_segment.ended_at)
      end
      let(:first_slice) { billing_segment.dup }
      let(:second_slice) { second_segment.dup }

      before do
        create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region_filter, value: "eu")
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, properties: {region: "eu"}, timestamp: billing_segment.started_at + 1.hour)
        create(:event, organization:, customer:, external_subscription_id: second_contract.external_id,
          code: billable_metric.code, properties: {region: "us"}, timestamp: second_segment.started_at + 2.hours)
      end

      it "keeps property buckets isolated by contract without persisting the supplied slices" do
        legacy_segment_count = LegacyBillingSegment.count
        targets = described_class.new(billing_segments: [first_slice, second_slice]).filter_targets

        expect(targets[billing_segment.target_key]).to eq(eu_filter.id => Event.where(external_subscription_id: contract.external_id).sole.created_at)
        expect(targets[second_segment.target_key]).to eq(nil => Event.where(external_subscription_id: second_contract.external_id).sole.created_at)
        expect([first_slice, second_slice]).to all(respond_to(:attributes))
        expect(LegacyBillingSegment.count).to eq(legacy_segment_count)
      end
    end

    context "with recurring usage on an unsaved segment" do
      let(:billable_metric) do
        create(:sum_billable_metric, organization:, field_name: "quantity", recurring: true)
      end
      let(:historical_event) do
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, properties: {quantity: 1}, timestamp: billing_segment.started_at - 1.month,
          created_at: billing_segment.started_at + 2.days)
      end
      let(:unsaved_recurring_segment) { billing_segment.dup }

      before do
        historical_event
        unsaved_recurring_segment
      end

      it "includes prior-period ingestion history without writing the segment" do
        legacy_segment_count = LegacyBillingSegment.count
        targets = described_class.new(billing_segments: [unsaved_recurring_segment]).filter_targets

        expect(targets).to eq(billing_segment.target_key => {nil => historical_event.created_at})
        expect(unsaved_recurring_segment).not_to respond_to(:persisted?)
        expect(LegacyBillingSegment.count).to eq(legacy_segment_count)
      end
    end

    context "with only an empty explicit product filter" do
      before do
        create(:product_filter, organization:, product:)
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: billing_segment.started_at + 1.hour)
      end

      it "routes unmatched usage to the default bucket without seeding the empty filter" do
        expect(filter_targets[billing_segment.target_key].keys).to eq([nil])
      end
    end

    context "with a plan-originated billing segment" do
      let(:catalog_plan) { create(:catalog_plan, organization:) }
      let(:contract) do
        create(:contract, organization:, customer:, catalog_plan:, external_id: "plan-contract",
          started_at: Time.zone.parse("2026-09-01"))
      end
      let(:contract_rate_card) do
        create(:plan_rate_card, organization:, catalog_plan:, rate_card:)
        Contracts::MaterializeRateCardsService.call!(contract:).contract_rate_cards.sole
      end
      let(:product_filter) { create(:product_filter, organization:, product:) }
      let(:broad_filter) { create(:product_filter, organization:, product:, created_at: 2.days.ago) }
      let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us]) }
      let(:billing_segment) do
        build(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
          cycle_started_at: Time.current.beginning_of_month, started_at: Time.current.beginning_of_month,
          ended_at: Time.current.end_of_month)
      end
      let(:event) do
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, properties: {"region" => "eu"}, timestamp: billing_segment.started_at + 1.hour)
      end

      before do
        create(:product_filter_value, organization:, product_filter: broad_filter, billable_metric_filter: region_filter, value: nil)
        create(:product_filter_value, organization:, product_filter:, billable_metric_filter: region_filter, value: "eu")
      end

      it "selects the precise plan filter while reporting both matching buckets" do
        expect(contract_rate_card.rate_card).to eq(rate_card)
        target_filter = Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment:)
        matching = Events::BillingPeriodFilters::EventMatchingService.call(target_filter:, event:)

        expect(matching.filter).to eq(product_filter)
        expect(filter_targets[billing_segment.target_key]).to eq(
          broad_filter.id => event.created_at,
          product_filter.id => event.created_at
        )
      end
    end
  end
end
