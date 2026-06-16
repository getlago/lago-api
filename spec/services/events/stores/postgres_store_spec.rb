# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::PostgresStore do
  it_behaves_like "an event store", with_event_duplication: false do
    def create_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil, event_charge: nil)
      create(
        :event,
        transaction_id: transaction_id,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: timestamp,
        properties: properties.merge(billable_metric.field_name => value),
        precise_total_amount_cents: value
      )
    end

    def create_enriched_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code, charge_filter: nil, enriched_at: nil)
      event = create(
        :event,
        transaction_id:,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp:,
        properties:
      )

      create(
        :enriched_event,
        subscription:,
        event:,
        charge:,
        charge_filter_id: charge_filter&.id,
        value:,
        decimal_value: value&.to_i&.to_d
      )
    end

    def format_timestamp(timestamp, precision: nil)
      Time.zone.parse(timestamp)
    end
  end

  describe "#distinct_codes_and_property_combinations" do
    subject(:event_store) { described_class.new(subscription:, boundaries:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:, external_id: "sub_id") }

    let(:boundaries) do
      {
        from_datetime: Time.zone.parse("2024-01-01 00:00:00"),
        to_datetime: Time.zone.parse("2024-01-31 23:59:59")
      }
    end

    let(:create_event) do
      lambda do |properties:, timestamp: Time.zone.parse("2024-01-10 00:00:00"), code: "api_calls"|
        create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp:,
          properties:
        )
      end
    end

    before do
      create_event.call(properties: {"region" => "eu", "provider" => "aws"})
      create_event.call(properties: {"region" => "eu", "provider" => "aws"})
      create_event.call(properties: {"region" => "us", "provider" => "gcp"})
      create_event.call(properties: {"region" => "eu", "extra" => "ignored"})
    end

    it "returns the distinct property combinations sliced to the filter keys" do
      result = event_store.distinct_codes_and_property_combinations(
        codes: ["api_calls"],
        filter_keys: %w[region provider]
      )

      expect(result).to match_array([
        ["api_calls", {"region" => "eu", "provider" => "aws"}],
        ["api_calls", {"region" => "us", "provider" => "gcp"}],
        ["api_calls", {"region" => "eu"}]
      ])
    end

    it "ignores property keys that are not filter keys" do
      result = event_store.distinct_codes_and_property_combinations(
        codes: ["api_calls"],
        filter_keys: ["region"]
      )

      expect(result).to match_array([
        ["api_calls", {"region" => "eu"}],
        ["api_calls", {"region" => "us"}]
      ])
    end

    context "when no filter keys are given" do
      it "returns the default bucket combination" do
        result = event_store.distinct_codes_and_property_combinations(
          codes: ["api_calls"],
          filter_keys: []
        )

        expect(result).to eq([["api_calls", {}]])
      end
    end

    context "with events outside the boundaries" do
      before do
        create_event.call(
          properties: {"region" => "apac", "provider" => "azure"},
          timestamp: Time.zone.parse("2024-02-05 00:00:00")
        )
      end

      it "excludes them from the combinations" do
        result = event_store.distinct_codes_and_property_combinations(
          codes: ["api_calls"],
          filter_keys: %w[region provider]
        )

        expect(result).not_to include(["api_calls", {"region" => "apac", "provider" => "azure"}])
      end
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
          subscription:,
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

        expect(tied_events.map { |event| store_for(event).count }).to eq([2, 3, 4])
      end

      it "assigns distinct positions when created_at is also tied" do
        tied_events = (1..3).map { create_event(timestamp:, created_at: timestamp) }

        expect(tied_events.map { |event| store_for(event).count }).to match_array([2, 3, 4])
      end

      it "counts all events sharing the timestamp when no event filter is given" do
        create_event(timestamp:, created_at: timestamp + 1.second)
        create_event(timestamp:, created_at: timestamp + 2.seconds)

        event_store = described_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries: {
            from_datetime: subscription.started_at.beginning_of_day,
            to_datetime: subscription.started_at.end_of_month.end_of_day,
            max_timestamp: timestamp
          },
          filters: {}
        )

        expect(event_store.count).to eq(3)
      end
    end
  end
end
