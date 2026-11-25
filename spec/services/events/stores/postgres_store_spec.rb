# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::PostgresStore do
  it_behaves_like "an event store", with_event_duplication: false do
    def create_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil, event_charge: nil, created_at: nil)
      attributes = {
        transaction_id: transaction_id,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: timestamp,
        properties: properties.merge(billable_metric.field_name => value),
        precise_total_amount_cents: value
      }
      attributes[:created_at] = created_at if created_at

      create(:event, **attributes)
    end

    def format_timestamp(timestamp, precision: nil)
      Time.zone.parse(timestamp)
    end
  end

  describe "#sum" do
    let(:field_name) { "value' OR FALSE) --" }
    let(:billable_metric) { create(:sum_billable_metric, field_name:) }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: 1.day.ago) }
    let(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries: {
          from_datetime: subscription.started_at.beginning_of_day,
          to_datetime: Time.current.end_of_day
        }
      ).tap do |store|
        store.aggregation_property = field_name
        store.numeric_property = true
      end
    end

    it "safely handles special characters in the aggregation property" do
      create(
        :event,
        organization:,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: Time.current,
        properties: {field_name => 2}
      )

      expect(event_store.sum.value).to eq(2)
    end
  end

  describe "#grouped_prorated_unique_count" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
    let(:subscription) { create(:subscription, customer:, started_at: Time.utc(2026, 10, 1)) }
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :unique_count_agg, recurring: true, field_name: "unique_id") }
    let(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries: {
          from_datetime: Time.utc(2026, 11, 1, 4),
          to_datetime: Time.utc(2026, 11, 2, 5) - Rational(1, 1_000_000),
          charges_duration: 30
        },
        filters: {grouped_by: ["region"]}
      ).tap do |store|
        store.aggregation_property = billable_metric.field_name
        store.use_from_boundary = false
      end
    end

    before do
      create(:event, organization:, subscription:, customer:, code: billable_metric.code,
        timestamp: Time.utc(2026, 10, 15), properties: {unique_id: "a", region: "EU"})
      create(:event, organization:, subscription:, customer:, code: billable_metric.code,
        timestamp: Time.utc(2026, 11, 1, 4, 30), properties: {unique_id: "a", region: "EU", operation_type: "remove"})
    end

    it "includes removal day in the customer timezone across the fall-back transition" do
      result = event_store.grouped_prorated_unique_count.sole

      # New York's November 1 lasts 25 hours but contributes one of the cycle's 30 calendar days.
      expect(result.groups).to eq("region" => "EU")
      expect(result.value.round(8)).to eq((1.to_d / 30).round(8))
    end
  end

  describe "#count" do
    context "when the upper boundary is a pay-in-advance event (max_timestamp)" do
      let(:billable_metric) { create(:billable_metric) }
      let(:organization) { billable_metric.organization }
      let(:customer) { create(:customer, organization:) }
      let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
      let(:timestamp) { subscription.started_at + 1.day }

      let(:previous_event) { create_event(timestamp: timestamp - 1.hour, created_at: timestamp - 1.hour) }
      let(:next_event) { create_event(timestamp: timestamp + 1.hour, created_at: timestamp + 1.hour) }

      def create_event(timestamp:, created_at:)
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp:,
          created_at:
        )
      end

      def store_for(event)
        described_class.new(
          code: billable_metric.code,
          billing_context: Billing::Context.from(subscription:),
          boundaries: {
            from_datetime: subscription.started_at.beginning_of_day,
            to_datetime: subscription.started_at.end_of_month.end_of_day,
            max_timestamp: event.timestamp
          },
          filters: {event: Events::CommonFactory.new_instance(source: event)}
        )
      end

      before do
        previous_event
        next_event
      end

      it "assigns a distinct position to each event sharing the boundary timestamp" do
        tied_events = (1..3).map { |i| create_event(timestamp:, created_at: timestamp + i.seconds) }

        expect(tied_events.map { |event| store_for(event).count.value }).to eq([2, 3, 4])
      end

      it "assigns distinct positions when created_at is also tied" do
        tied_events = (1..3).map { create_event(timestamp:, created_at: timestamp) }

        expect(tied_events.map { |event| store_for(event).count.value }).to match_array([2, 3, 4])
      end

      it "counts all events sharing the timestamp when no event filter is given" do
        create_event(timestamp:, created_at: timestamp + 1.second)
        create_event(timestamp:, created_at: timestamp + 2.seconds)

        event_store = described_class.new(
          code: billable_metric.code,
          billing_context: Billing::Context.from(subscription:),
          boundaries: {
            from_datetime: subscription.started_at.beginning_of_day,
            to_datetime: subscription.started_at.end_of_month.end_of_day,
            max_timestamp: timestamp
          },
          filters: {}
        )

        expect(event_store.count).to eq(Events::Stores::BaseStore::AggregationResult.new(value: 3, events_count: 3))
      end
    end
  end

  describe "#active_unique_property?" do
    let(:billable_metric) { create(:billable_metric) }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:, started_at: timestamp - 1.day) }
    let(:timestamp) { Time.zone.parse("2026-10-06T15:18:14.156149Z") }
    let(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries: {from_datetime: subscription.started_at, to_datetime: timestamp + 1.day}
      ).tap { |store| store.aggregation_property = "user_id" }
    end
    let(:previous_event) do
      create(
        :event,
        id: "00000000-0000-4000-8000-000000000001",
        organization:,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:,
        created_at: timestamp,
        properties: {user_id: "A"}
      )
    end
    let(:current_event) do
      create(
        :event,
        id: "00000000-0000-4000-8000-000000000002",
        organization:,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp:,
        created_at: timestamp,
        properties: {user_id: "A"}
      )
    end
    let(:legacy_event) do
      Events::Common.new(
        id: current_event.id,
        transaction_id: current_event.transaction_id,
        timestamp: current_event.timestamp,
        properties: current_event.properties
      )
    end

    it "uses created_at and id to order persisted events tied on timestamp" do
      previous_event

      expect(event_store).to be_active_unique_property(current_event)
    end

    it "uses the legacy scoped subquery when a persisted event has no created_at" do
      previous_event

      expect(event_store).to be_active_unique_property(legacy_event)
    end
  end

  describe "#weighted_sum" do
    context "when the period is zero-length and holds no event" do
      let(:billable_metric) { create(:weighted_sum_billable_metric) }
      let(:organization) { billable_metric.organization }
      let(:customer) { create(:customer, organization:) }
      let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse("2023-03-15")) }
      let(:datetime) { subscription.started_at.beginning_of_day }

      let(:event_store) do
        described_class.new(
          code: billable_metric.code,
          billing_context: Billing::Context.from(subscription:),
          boundaries: {
            from_datetime: datetime,
            to_datetime: datetime,
            charges_duration: 31
          }
        )
      end

      # NOTE: from_datetime == to_datetime makes both boundary rows identical, so the UNION in the
      #       events CTE dedups them into one. events_count must not go negative.
      it "returns a zero events count" do
        result = event_store.weighted_sum

        expect(result.events_count).to eq(0)
      end
    end
  end

  describe "#grouped_weighted_sum" do
    let(:group_value) { "europe' OR TRUE --" }
    let(:billable_metric) { create(:weighted_sum_billable_metric) }
    let(:organization) { billable_metric.organization }
    let(:customer) { create(:customer, organization:) }
    let(:started_at) { Time.zone.parse("2023-03-01") }
    let(:subscription) { create(:subscription, customer:, started_at:) }
    let(:event_store) do
      described_class.new(
        code: billable_metric.code,
        billing_context: Billing::Context.from(subscription:),
        boundaries: {
          from_datetime: started_at,
          to_datetime: started_at.end_of_month.end_of_day,
          charges_duration: 31
        },
        filters: {grouped_by: ["region"]}
      ).tap do |store|
        store.aggregation_property = billable_metric.field_name
        store.numeric_property = true
      end
    end

    it "safely handles special characters in grouped values" do
      create(
        :event,
        organization:,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: started_at + 1.day,
        properties: {billable_metric.field_name => 2, "region" => group_value}
      )

      expect(event_store.grouped_weighted_sum.sole.groups).to eq("region" => group_value)
    end
  end

  describe "#resent_after_watermark?" do
    let(:subscription) { create(:subscription) }
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization: subscription.organization) }
    let(:event_store) do
      described_class.new(code: billable_metric.code, billing_context: Billing::Context.from(subscription:), boundaries: {}, filters: {})
    end
    let(:period) { RecurringAggregationSnapshots::FetchService::Period.new(to_datetime: Time.current, watermark: Time.current) }

    it "never finds one, as a re-sent transaction_id is rejected" do
      expect(event_store.resent_after_watermark?(period)).to be(false)
    end
  end
end
