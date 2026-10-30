# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::Fees::RecurringBreakdownService do
  subject(:result) { described_class.call(fee:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "users", recurring: true) }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:product_filter) { nil }
  let(:rate_card) { create(:rate_card, organization:, product:, product_filter:) }
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
      cycle_started_at: Time.utc(2026, 8, 1),
      started_at: Time.utc(2026, 8, 1),
      ended_at: BillingSegment.inclusive_end(Time.utc(2026, 9, 1)),
      billing_at: Time.utc(2026, 9, 1)
    )
  end
  let(:charges_from_datetime) { billing_segment.started_at.iso8601(6) }
  let(:fee) do
    create(
      :fee,
      organization:,
      invoice:,
      subscription: nil,
      fee_type: :product,
      invoiceable: product,
      contract:,
      contract_rate_card:,
      rate_card_rate:,
      product_filter:,
      units: 17,
      properties: {
        "charges_from_datetime" => charges_from_datetime,
        "charges_to_datetime" => billing_segment.ended_at.iso8601(6),
        "charges_duration" => 31
      }
    )
  end

  def create_event(timestamp, properties)
    create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: billable_metric.code, timestamp:, properties:)
  end

  def breakdown_rows
    result.breakdown.map { [it.date.to_s, it.action, it.amount, it.duration, it.total_duration] }
  end

  context "with a sum metric" do
    before do
      create_event(Time.utc(2026, 7, 10), {"users" => 12})
      create_event(Time.utc(2026, 8, 11), {"users" => 5})
      create(:event, organization:, customer:, external_subscription_id: "another-contract", code: billable_metric.code, timestamp: Time.utc(2026, 8, 12), properties: {"users" => 100})
    end

    it "lists the units carried into the segment, then the units added during it" do
      expect(result).to be_success
      expect(breakdown_rows).to eq(
        [
          ["2026-08-01", "add", 12, 31, 31], # carried from Jul 10, used Aug 1 to Aug 31
          ["2026-08-11", "add", 5, 21, 31] # used Aug 11 to Aug 31
        ]
      )
    end
  end

  context "with a unique count metric" do
    let(:billable_metric) { create(:unique_count_billable_metric, organization:, field_name: "user_id", recurring: true) }

    before do
      create_event(Time.utc(2026, 7, 10), {"user_id" => "111"})
      create_event(Time.utc(2026, 8, 11), {"user_id" => "222"})
    end

    it "lists each item carried into the segment, then each item added during it" do
      expect(breakdown_rows).to eq(
        [
          ["2026-08-01", "add", 1, 31, 31],
          ["2026-08-11", "add", 1, 21, 31]
        ]
      )
    end
  end

  context "with product filters" do
    let(:region) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us]) }
    let(:eu_filter) { create(:product_filter, organization:, product:) }

    before do
      create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region, value: "eu")
      create_event(Time.utc(2026, 7, 10), {"users" => 12, "region" => "eu"})
      create_event(Time.utc(2026, 8, 11), {"users" => 5, "region" => "eu"})
      create_event(Time.utc(2026, 8, 12), {"users" => 7, "region" => "us"})
    end

    it "only breaks down the events no filter of the product matches, as the fee billed them" do
      expect(breakdown_rows).to eq([["2026-08-12", "add", 7, 20, 31]])
    end

    context "when the fee bills a product filter" do
      let(:product_filter) { eu_filter }

      it "only breaks down the events of that filter" do
        expect(breakdown_rows).to eq(
          [
            ["2026-08-01", "add", 12, 31, 31],
            ["2026-08-11", "add", 5, 21, 31]
          ]
        )
      end
    end
  end

  context "when the metric has no breakdown" do
    let(:billable_metric) { create(:weighted_sum_billable_metric, organization:, recurring: true) }

    it "fails" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      expect(result.error.code).to eq("unsupported_aggregation_type")
    end
  end

  context "when no billing segment of the rate card starts with the fee" do
    let(:charges_from_datetime) { (billing_segment.started_at + 1.day).iso8601(6) }

    it "fails" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.error_code).to eq("billing_segment_not_found")
    end
  end
end
