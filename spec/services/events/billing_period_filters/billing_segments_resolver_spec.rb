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
    create(
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
        create(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
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
