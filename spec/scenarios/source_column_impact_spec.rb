# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Source Column Impact on Billing", type: :scenario do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0) }
  let(:subscription) { create(:subscription, customer:, plan:, started_at: 1.month.ago) }
  let(:code) { "code_001" }
  let(:billable_metric) { create(:billable_metric, organization:, code:, aggregation_type: "sum_agg", field_name: "value") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"}) }
  let(:add_on) { create(:add_on, organization:, amount_cents: 10, code:) }

  before do
    charge
  end

  # there is no unique constraint on code for billable_metric and fixed_charge (add_on) across db tables.
  # this means we can have billable_metrics and add_ons with the same code.
  
  describe "when fixed charge events pollute usage aggregations by code coincidence" do
    context "with sum aggregation" do
      it "does not include fixed charge events in usage calculations" do
        create_list(:event, 2,
          organization:,
          subscription:,
          code:,
          source: "usage",
          properties: { value: 5 },
          timestamp: 1.day.ago
        )

        create_list(:event, 2,
          organization:,
          subscription:,
          code:,
          source: "fixed_charge",
          properties: { value: 10 },
          timestamp: 1.day.ago
        )

        result = Fees::ChargeService.call(
          invoice: nil,
          charge:,
          subscription:,
          boundaries: {
            charges_from_datetime: 2.days.ago,
            charges_to_datetime: Time.current
          }
        )

        expect(result.fees.first.units).to eq(10)
        expect(result.fees.first.amount_cents).to eq(10000)
      end
    end

    context "with count aggregation" do
      let(:billable_metric) do
        create(:billable_metric, organization:, code:, aggregation_type: "count_agg")
      end

      it "does not include fixed charge events in usage calculations" do
        create_list(:event, 2,
          organization:,
          subscription:,
          code:,
          source: 'usage',
          properties: {},
          timestamp: 1.day.ago
        )

        create_list(:event, 2,
          organization:,
          subscription:,
          code:,
          source: 'fixed_charge',
          properties: {},
          timestamp: 1.day.ago
        )

        result = Fees::ChargeService.call(
          invoice: nil,
          charge:,
          subscription:,
          boundaries: {
            charges_from_datetime: 2.days.ago,
            charges_to_datetime: Time.current
          }
        )

        expect(result.fees.first.units).to eq(2)
        expect(result.fees.first.amount_cents).to eq(2000)
      end
    end

    context "with max aggregation" do
      let(:billable_metric) do
        create(:billable_metric, organization:, code:, aggregation_type: "max_agg", field_name: "value")
      end

      it "does not include fixed charge events in max calculations" do
        create(
          :event,
          organization:,
          subscription:,
          code:,
          source: 'usage',
          properties: { value: 7 },
          timestamp: 1.day.ago
        )

        create(
          :event,
          organization:,
          subscription:,
          code:,
          source: 'usage',
          properties: { value: 2 },
          timestamp: 1.day.ago
        )

        create(
          :event,
          organization:,
          subscription:,
          code:,
          source: 'fixed_charge',
          properties: { value: 15 },
          timestamp: 1.day.ago
        )

        result = Fees::ChargeService.call(
          invoice: nil,
          charge:,
          subscription:,
          boundaries: {
            charges_from_datetime: 2.days.ago,
            charges_to_datetime: Time.current
          }
        )

        expect(result.fees.first.units).to eq(7)
        expect(result.fees.first.amount_cents).to eq(7000) 
      end
    end

    context "with unique count aggregation" do
      let(:billable_metric) do
        create(:billable_metric, organization:, code:, aggregation_type: "unique_count_agg", field_name: "item_id")
      end

      it "does not include fixed charge events in unique count calculations" do
        create_list(:event, 2,
          organization:,
          subscription:,
          code:,
          source: "usage",
          properties: { item_id: "usage_1" },
          timestamp: 1.day.ago
        )

        create_list(:event, 2,
          organization:,
          subscription:,
          code:,
          source: "fixed_charge",
          properties: { item_id: "fixed_1" },
          timestamp: 1.day.ago
        )

        result = Fees::ChargeService.call(
          invoice: nil,
          charge:,
          subscription:,
          boundaries: {
            charges_from_datetime: 2.days.ago,
            charges_to_datetime: Time.current
          }
        )

        expect(result.fees.first.units).to eq(1)
        expect(result.fees.first.amount_cents).to eq(1000)
      end
    end
  end

  describe "when fixed charge events affect cached aggregations" do
    it "pollutes cached aggregation data" do
      create_list(:event, 2,
        organization:,
        subscription:,
        code:,
        source: 'usage',
        properties: { value: 5 },
        timestamp: 1.day.ago
      )

      create_list(:event, 2,
        organization:,
        subscription:,
        code:,
        source: 'fixed_charge',
        properties: { value: 10 },
        timestamp: 1.day.ago
      )

      # First billing cycle -> should cache incorrect data
      result1 = Fees::ChargeService.call(
        invoice: nil,
        charge:,
        subscription:,
        boundaries: {
          charges_from_datetime: 2.days.ago,
          charges_to_datetime: 1.day.ago
        }
      )

      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'usage',
        properties: { value: 8 },
        timestamp: Time.current
      )

      # Second billing cycle
      result2 = Fees::ChargeService.call(
        invoice: nil,
        charge:,
        subscription:,
        boundaries: {
          charges_from_datetime: 1.day.ago,
          charges_to_datetime: Time.current
        }
      )

      # NOTE: WTF are we testing here?
      expect(result2.fees.first.units).to eq(8)
    end
  end

  describe "when fixed charge events affect grouped aggregations" do
    let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "10", grouped_by: ["region"]}) }

    it "does not include fixed charge events in grouped aggregations" do
      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'usage',
        properties: { value: 5, region: "us-east" },
        timestamp: 1.day.ago
      )

      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'usage',
        properties: { value: 3, region: "us-west" },
        timestamp: 1.day.ago
      )

      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'fixed_charge',
        properties: { value: 10, region: "us-east" },
        timestamp: 1.day.ago
      )

      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'fixed_charge',
        properties: { value: 7, region: "us-west" },
        timestamp: 1.day.ago
      )

      result = Fees::ChargeService.call(
        invoice: nil,
        charge:,
        subscription:,
        boundaries: {
          charges_from_datetime: 2.days.ago,
          charges_to_datetime: Time.current
        }
      )

      expect(result.fees.count).to eq(2)

      us_east_fee = result.fees.find { |f| f.grouped_by["region"] == "us-east" }
      us_west_fee = result.fees.find { |f| f.grouped_by["region"] == "us-west" }

      expect(us_east_fee.units).to eq(5)
      expect(us_west_fee.units).to eq(3)
    end
  end

  describe "when fixed charge events affect customer usage calculations" do
    it "does not include fixed charge events in customer usage calculations" do
      # Create usage events
      create_list(:event, 2,
        organization:,
        subscription:,
        code:,
        source: 'usage',
        properties: { value: 5 },
        timestamp: 1.day.ago
      )

      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'fixed_charge',
        properties: { value: 10 },
        timestamp: 1.day.ago
      )

      usage_service = Invoices::CustomerUsageService.with_ids(
        organization_id: organization.id,
        customer_id: customer.id,
        subscription_id: subscription.id
      )

      result = usage_service.call

      expect(result.usage.fees.first.units).to eq("10.0")
      expect(result.usage.total_amount_cents).to eq(10000)
    end
  end

  describe "when fixed charge events affect lifetime usage calculations" do
    let(:lifetime_usage) { create(:lifetime_usage, organization:, subscription:, recalculate_current_usage: true) }

    it "does not include fixed charge events in lifetime usage calculations" do
      create_list(:event, 2,
        organization:,
        subscription:,
        code:,
        source: 'usage',
        properties: { value: 5 },
        timestamp: 1.day.ago
      )

      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'fixed_charge',
        properties: { value: 7 },
        timestamp: 1.day.ago
      )

      # lifetime_usage = subscription.create_lifetime_usage!(organization:)
      # lifetime_usage.update!(recalculate_current_usage: true)

      result = LifetimeUsages::CalculateService.call(lifetime_usage:)

      expect(result.lifetime_usage.current_usage_amount_cents).to eq(1000)
    end
  end

  describe "when fixed charge events affect event validation" do
    it "does not include fixed charge events in event validation" do
      create_list(:event, 2,
        organization:,
        subscription:,
        code:,
        source: 'usage',
        properties: { value: 5 },
        timestamp: 10.minutes.ago
      )

      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'fixed_charge',
        properties: { value: 7 },
        timestamp: 5.minutes.ago
      )

      # Force materialized view refresh
      Scenic.database.refresh_materialized_view(
        Events::LastHourMv.table_name,
        concurrently: false,
        cascade: false
      )

      expect(Events::LastHourMv.count).to eq(2)
    end
  end

  describe "when fixed charge events affect API responses" do
    it "includes fixed charge events in API responses" do
      create_list(:event, 2,
        organization:,
        subscription:,
        code:,
        source: 'usage',
        properties: { value: 5 },
        timestamp: 1.day.ago
      )

      create(
        :event,
        organization:,
        subscription:,
        code:,
        source: 'fixed_charge',
        properties: { value: 7 },
        timestamp: 1.day.ago
      )

      events_query = EventsQuery.new(
        organization:,
        pagination: nil,
        filters: {}
      )

      result = events_query.call

      expect(result.events.count).to eq(3)
      expect(result.events.map(&:source)).to include('fixed_charge')
    end
  end
end 