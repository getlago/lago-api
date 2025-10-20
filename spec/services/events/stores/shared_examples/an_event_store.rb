# frozen_string_literal: true

RSpec.shared_examples "an event store" do |with_event_duplication: true|
  subject(:event_store) do
    described_class.new(
      code:,
      subscription:,
      boundaries:,
      filters: {
        grouped_by:,
        grouped_by_values:,
        matching_filters:,
        ignored_filters:
      }
    )
  end

  let(:billable_metric) { create(:billable_metric, field_name: "value", code: "bm:code") }
  let(:organization) { billable_metric.organization }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, started_at:) }

  let(:started_at) { DateTime.parse("2023-03-15") }
  let(:code) { billable_metric.code }

  let(:subscription_started_at) { subscription.started_at.beginning_of_day }
  let(:boundaries) do
    {
      from_datetime: subscription_started_at,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_duration: 31
    }
  end

  let(:grouped_by) { nil }
  let(:grouped_by_values) { nil }
  let(:with_grouped_by_values) { nil }
  let(:matching_filters) { {} }
  let(:ignored_filters) { [] }

  let(:events) do
    events = [
      create_event(
        timestamp: subscription_started_at + 1.day,
        value: 1,
        properties: {"region" => "europe", "country" => "france", "city" => "paris"},
        transaction_id: SecureRandom.uuid
      ),
      create_event(
        timestamp: subscription_started_at + 2.days,
        value: 2,
        properties: {},
        transaction_id: SecureRandom.uuid
      ),
      create_event(
        timestamp: subscription_started_at + 3.days,
        value: 3,
        properties: {"region" => "europe", "country" => "france"},
        transaction_id: SecureRandom.uuid
      ),
      create_event(
        timestamp: subscription_started_at + 4.days,
        value: 4,
        properties: {},
        transaction_id: SecureRandom.uuid
      ),
      create_event(
        timestamp: subscription_started_at + 5.days,
        value: with_event_duplication ? 10 : 5,
        properties: {"region" => "europe", "country" => "united kingdom", "city" => "london"},
        transaction_id: SecureRandom.uuid
      )
    ]

    if with_event_duplication
      last_event = events.pop
      events << create_event(
        timestamp: last_event.timestamp,
        value: 5,
        properties: last_event.properties,
        transaction_id: last_event.transaction_id
      )
    end

    events
  end

  def create_european_event(country:, city:, value:, timestamp:)
    create_event(
      timestamp:,
      value:,
      properties: {"region" => "europe", "country" => country, "city" => city},
      transaction_id: SecureRandom.uuid
    )
  end

  def create_events_for_filters
    create_european_event(country: "united kingdom", city: "manchester", value: -1, timestamp: subscription_started_at + 6.days)
    create_european_event(country: "france", city: "cambridge", value: -2, timestamp: subscription_started_at + 7.days)
    create_european_event(country: "france", city: "caen", value: -3, timestamp: subscription_started_at + 8.days)
    create_european_event(country: "germany", city: "berlin", value: -4, timestamp: subscription_started_at + 9.days)
    create_european_event(country: "united kingdom", city: "cambridge", value: -5, timestamp: subscription_started_at + 10.days)
  end

  before do
    events
    force_deduplication if respond_to?(:force_deduplication)
  end

  describe "#events" do
    it "returns the events" do
      retrieved_events = event_store.events.to_a

      expect(retrieved_events.count).to eq(5)
      expect(retrieved_events).to match_array(events)
      # we need to check value because the duplicate has the same id so array equality is not sufficiant
      expect(retrieved_events.map { |e| e.properties[billable_metric.field_name].to_s }).to match_array(["1", "2", "3", "4", "5"])
    end

    context "when ordered is true" do
      it "returns the events ordered by timestamp" do
        retrieved_events = event_store.events(ordered: true)

        expect(retrieved_events).to eq(events)
        # we need to check value because the duplicate has the same id so array equality is not sufficiant
        expect(retrieved_events.map { |e| e.properties[billable_metric.field_name].to_s }).to eq(["1", "2", "3", "4", "5"])
      end
    end
  end

  describe "#count" do
    it "returns the number of unique events" do
      expect(event_store.count).to eq(5)
    end

    context "with grouped_by_values" do
      let(:grouped_by_values) { {"region" => "europe"} }

      it "returns the number of unique events" do
        expect(event_store.count).to eq(3)
      end

      context "when grouped_by_values value is nil" do
        let(:grouped_by_values) { {"region" => nil} }

        it "returns the number of unique events" do
          expect(event_store.count).to eq(2)
        end
      end
    end

    context "with filters" do
      let(:matching_filters) { {"region" => ["europe"], "country" => ["france", "united kingdom"]} }
      let(:ignored_filters) { [{"city" => ["caen"]}, {"city" => ["cambridge", "london"], "country" => ["united kingdom"]}] }

      before { create_events_for_filters }

      it "returns the number of unique events" do
        # We include:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, caen
        # - europe, france, cambridge
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # - europe, united kingdom, manchester
        # Then exclude:
        # - europe, france, caen
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # We should have 4 events:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, cambridge
        # - europe, united kingdom, manchester
        expect(event_store.count).to eq(4)
      end

      # We faced an issue where Arel caused a Stack Level Too Deep error due to how the request `OR` conditons are build.
      # This test is used to ensure that we can handle this situation.
      # This test fails when using the Arel version.
      context "when there are many filters" do
        let(:matching_filters) { {"region" => ["europe"], "country" => ["france", "united kingdom"], "city" => ["paris", "london", "cambridge", "caen", "manchester"]} }
        let(:ignored_filters) do
          Array.new(200) do |i|
            {"region" => [Faker::Alphanumeric.alphanumeric(number: 10)], "city" => [Faker::Alphanumeric.alphanumeric(number: 10)]}
          end
        end

        # This function is used to simulate a nested stack. Otherwise we'll reach the Clickhouse query size limits
        # before reaching a stack error.
        def within_nested_stack(stack_number, &block)
          if stack_number > 0
            within_nested_stack(stack_number - 1, &block)
          else
            yield
          end
        end

        it "does not raise an error" do
          within_nested_stack(8200) do
            expect do
              event_store.count
            end.not_to raise_error
          end
        end
      end
    end

    context "with max timestamp" do
      let(:boundaries) do
        {
          from_datetime: subscription.started_at.beginning_of_day,
          to_datetime: subscription.started_at.end_of_month.end_of_day,
          max_timestamp: subscription.started_at.beginning_of_day.end_of_day + 2.days,
          charges_duration: 31
        }
      end

      it "returns the number of unique events" do
        expect(event_store.count).to eq(2)
      end
    end

    if with_event_duplication
      context "with only duplicated transaction_id" do
        before do
          event = events.first

          create_event(
            timestamp: subscription_started_at + 5.days,
            value: 1,
            properties: {},
            transaction_id: event.transaction_id
          )
        end

        it "takes the event into account" do
          expect(event_store.count).to eq(6)
        end
      end
    end
  end

  describe "#with_grouped_by_values" do
    let(:with_grouped_by_values) { {"region" => "europe"} }

    it "applies the grouped_by_values in the block" do
      event_store.with_grouped_by_values(with_grouped_by_values) do
        expect(event_store.count).to eq(3)
      end
    end
  end

  describe "#distinct_codes" do
    before do
      create_event(
        timestamp: subscription_started_at + (1..10).to_a.sample.days,
        value: "value",
        transaction_id: SecureRandom.uuid,
        code: "other_code"
      )
    end

    it "returns the distinct event codes" do
      expect(event_store.distinct_codes).to match_array([code, "other_code"])
    end
  end

  describe "#grouped_count" do
    let(:grouped_by) { %w[region] }

    it "returns the number of unique events grouped by the provided group" do
      result = event_store.grouped_count

      expect(result).to match_array([{groups: {"region" => nil}, value: 2}, {groups: {"region" => "europe"}, value: 3}])
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[region country] }

      it "returns the number of unique events grouped by the provided groups" do
        result = event_store.grouped_count

        expect(result).to match_array([
          {groups: {"country" => "france", "region" => "europe"}, value: 2},
          {groups: {"country" => nil, "region" => nil}, value: 2},
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: 1}
        ])
      end
    end
  end

  describe "#sum_precise_total_amount_cents" do
    it "returns the sum of precise_total_amount_cent values" do
      expect(event_store.sum_precise_total_amount_cents).to eq(15)
    end
  end

  describe "#grouped_sum_precise_total_amount_cents" do
    let(:grouped_by) { %w[region] }

    it "returns the sum of values grouped by the provided group" do
      result = event_store.grouped_sum_precise_total_amount_cents

      expect(result).to match_array([{groups: {"region" => nil}, value: 6}, {groups: {"region" => "europe"}, value: 9}])
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[region country] }

      it "returns the sum of values grouped by the provided groups" do
        result = event_store.grouped_sum_precise_total_amount_cents

        expect(result).to match_array([
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: 5},
          {groups: {"country" => nil, "region" => nil}, value: 6},
          {groups: {"country" => "france", "region" => "europe"}, value: 4}
        ])
      end
    end

    context "with filters" do
      let(:matching_filters) { {"region" => ["europe"], "country" => ["france", "united kingdom"]} }
      let(:ignored_filters) { [{"city" => ["caen"]}, {"city" => ["cambridge", "london"], "country" => ["united kingdom"]}] }
      let(:grouped_by) { %w[region country] }

      before { create_events_for_filters }

      it "returns the sum filtered and grouped" do
        result = event_store.grouped_sum_precise_total_amount_cents

        # We include:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, caen
        # - europe, france, cambridge
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # - europe, united kingdom, manchester
        # Then exclude:
        # - europe, france, caen
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # We should have 2 events:
        # - europe, france, <nil> -> 3
        # - europe, france, paris -> 1
        # - europe, france, cambridge -> -2
        # - europe, united kingdom, manchester -> -1
        expect(result).to match_array([
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: -1},
          {groups: {"country" => "france", "region" => "europe"}, value: 2}
        ])
      end
    end
  end

  describe "#active_unique_property?" do
    before { event_store.aggregation_property = billable_metric.field_name }

    it "returns false when no previous events exist" do
      event = create_event(timestamp: subscription_started_at + 2.days, value: 999)

      expect(event_store).not_to be_active_unique_property(event)
    end

    context "when event is already active" do
      it "returns true if the event property is active" do
        event = create_event(timestamp: subscription_started_at + 3.days, value: 2)

        expect(event_store).to be_active_unique_property(event)
      end
    end

    context "with a previous removed event" do
      before do
        create_event(timestamp: subscription_started_at + 2.days + 1.hour, value: 2, properties: {operation_type: "remove"})
      end

      it "returns false" do
        event = create_event(timestamp: subscription_started_at + 3.days, value: 2)

        expect(event_store).not_to be_active_unique_property(event)
      end
    end
  end

  describe "#unique_count" do
    it "returns the number of unique active event properties" do
      create_event(timestamp: subscription_started_at + 2.days + 1.hour, value: 2, properties: {operation_type: "remove"})

      event_store.aggregation_property = billable_metric.field_name

      expect(event_store.unique_count).to eq(4) # 5 events added / 1 removed
    end
  end

  describe "#grouped_unique_count" do
    let(:grouped_by) { %w[region country city] }
    let(:started_at) { Time.zone.parse("2023-03-01") }

    before do
      event_store.aggregation_property = billable_metric.field_name
    end

    it "returns the unique count of event properties" do
      result = event_store.grouped_unique_count

      expect(result).to match_array([
        {groups: {"city" => nil, "country" => "france", "region" => "europe"}, value: 1},
        {groups: {"city" => "paris", "country" => "france", "region" => "europe"}, value: 1},
        {groups: {"city" => "london", "country" => "united kingdom", "region" => "europe"}, value: 1},
        {groups: {"city" => nil, "country" => nil, "region" => nil}, value: 2}
      ])
    end

    context "with no events" do
      let(:events) { [] }

      it "returns the unique count of event properties" do
        result = event_store.grouped_unique_count
        expect(result.count).to eq(0)
      end
    end
  end

  describe "#events_values" do
    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the value attached to each event" do
      expect(event_store.events_values).to eq([1, 2, 3, 4, 5])
    end

    context "with limit" do
      it "returns the value attached to each event" do
        expect(event_store.events_values(limit: 2)).to eq([1, 2])
      end
    end

    context "when exclude_event is true" do
      subject(:event_store) do
        described_class.new(
          code:,
          subscription:,
          boundaries:,
          filters: {
            grouped_by:,
            grouped_by_values:,
            matching_filters:,
            ignored_filters:,
            event:
          }
        )
      end

      let(:event) do
        create_event(timestamp: subscription_started_at + 1.day, value: 6)
      end

      it "excludes current event but returns the value attached to other events" do
        event

        expect(event_store.events_values(exclude_event: true)).to eq([1, 2, 3, 4, 5])
      end
    end
  end

  describe "#last_event" do
    it "returns the last event" do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.last_event.transaction_id).to eq(events.last.transaction_id)
    end
  end

  describe "#grouped_last_event" do
    let(:grouped_by) { %w[region] }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the last events grouped by the provided group" do
      result = event_store.grouped_last_event

      expect(result).to match_array([
        {groups: {"region" => nil}, timestamp: format_timestamp("2023-03-19 00:00:00.000"), value: 4},
        {groups: {"region" => "europe"}, timestamp: format_timestamp("2023-03-20 00:00:00.000"), value: 5}
      ])
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[region country] }

      it "returns the last events grouped by the provided groups" do
        result = event_store.grouped_last_event

        expect(result).to match_array([
          {groups: {"country" => "france", "region" => "europe"}, timestamp: format_timestamp("2023-03-18 00:00:00.000"), value: 3},
          {groups: {"country" => nil, "region" => nil}, timestamp: format_timestamp("2023-03-19 00:00:00.000"), value: 4},
          {groups: {"country" => "united kingdom", "region" => "europe"}, timestamp: format_timestamp("2023-03-20 00:00:00.000"), value: 5}
        ])
      end
    end

    context "with filters" do
      let(:matching_filters) { {"region" => ["europe"], "country" => ["france", "united kingdom"]} }
      let(:ignored_filters) { [{"city" => ["caen"]}, {"city" => ["cambridge", "london"], "country" => ["united kingdom"]}] }
      let(:grouped_by) { %w[region country] }

      before { create_events_for_filters }

      it "returns the last events filtered and grouped" do
        result = event_store.grouped_last_event

        # We include:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, caen
        # - europe, france, cambridge
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # - europe, united kingdom, manchester
        # Then exclude:
        # - europe, france, caen
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # We should have 4 events:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, cambridge
        # - europe, united kingdom, manchester
        # We keep last event for each group:
        # - europe, france, cambridge
        # - europe, united kingdom, manchester
        expect(result).to match_array(
          [
            {
              groups: {"country" => "france", "region" => "europe"},
              timestamp: format_timestamp("2023-03-22T00:00:00.000Z"),
              value: -2
            },
            {
              groups: {"country" => "united kingdom", "region" => "europe"},
              timestamp: format_timestamp("2023-03-21T00:00:00.000Z"),
              value: -1
            }
          ]
        )
      end
    end
  end

  describe "#max" do
    it "returns the max value" do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.max).to eq(5)
    end
  end

  describe "#grouped_max" do
    let(:grouped_by) { %w[region] }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the max values grouped by the provided group" do
      result = event_store.grouped_max

      expect(result).to match_array([
        {groups: {"region" => nil}, value: 4},
        {groups: {"region" => "europe"}, value: 5}
      ])
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[region country] }

      it "returns the max values grouped by the provided groups" do
        result = event_store.grouped_max

        expect(result).to match_array([
          {groups: {"country" => "france", "region" => "europe"}, value: 3},
          {groups: {"country" => nil, "region" => nil}, value: 4},
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: 5}
        ])
      end
    end

    context "with filters" do
      let(:matching_filters) { {"region" => ["europe"], "country" => ["france", "united kingdom"]} }
      let(:ignored_filters) { [{"city" => ["caen"]}, {"city" => ["cambridge", "london"], "country" => ["united kingdom"]}] }
      let(:grouped_by) { %w[region country] }

      before { create_events_for_filters }

      it "returns the max events filtered and grouped" do
        result = event_store.grouped_max

        # We include:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, caen
        # - europe, france, cambridge
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # - europe, united kingdom, manchester
        # Then exclude:
        # - europe, france, caen
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # We should have 2 events:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, cambridge
        # - europe, united kingdom, manchester
        # We keep "max" event for each group:
        # - europe, france, <nil>
        # - europe, united kingdom, manchester
        expect(result).to match_array([
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: -1},
          {groups: {"country" => "france", "region" => "europe"}, value: 3}
        ])
      end
    end
  end

  describe "#last" do
    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the last event value" do
      expect(event_store.last).to eq(5)
    end

    context "when there's no events" do
      let(:events) { [] }

      it "returns nil" do
        expect(event_store.last).to be_nil
      end
    end

    context "when the last event does not have a value" do
      let(:events) do
        [create_event(timestamp: subscription_started_at + 1.day, value: nil)]
      end

      it "returns nil" do
        expect(event_store.last).to be_nil
      end
    end
  end

  describe "#grouped_last" do
    let(:grouped_by) { %w[region] }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the value attached to each event prorated on the provided duration" do
      result = event_store.grouped_last

      expect(result).to match_array([
        {groups: {"region" => nil}, value: 4},
        {groups: {"region" => "europe"}, value: 5}
      ])
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[region country] }

      it "returns the last value for each provided groups" do
        result = event_store.grouped_last

        expect(result).to match_array([
          {groups: {"country" => nil, "region" => nil}, value: 4},
          {groups: {"country" => "france", "region" => "europe"}, value: 3},
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: 5}
        ])
      end
    end

    context "with filters" do
      let(:matching_filters) { {"region" => ["europe"], "country" => ["france", "united kingdom"]} }
      let(:ignored_filters) { [{"city" => ["caen"]}, {"city" => ["cambridge", "london"], "country" => ["united kingdom"]}] }
      let(:grouped_by) { %w[region country] }

      before { create_events_for_filters }

      it "returns the last values filtered and grouped" do
        result = event_store.grouped_last

        # We include:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, caen
        # - europe, france, cambridge
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # - europe, united kingdom, manchester
        # Then exclude:
        # - europe, france, caen
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # We should have 2 events:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, cambridge
        # - europe, united kingdom, manchester
        # We keep last event for each group:
        # - europe, france, cambridge
        # - europe, united kingdom, manchester
        expect(result).to match_array([
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: -1},
          {groups: {"country" => "france", "region" => "europe"}, value: -2}
        ])
      end
    end
  end

  describe "#sum" do
    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the sum of event properties" do
      expect(event_store.sum).to eq(15)
    end

    if with_event_duplication
      context "with only duplicated transaction_id" do
        before do
          event = events.first

          create_event(timestamp: subscription_started_at + 5.days, value: 100, transaction_id: event.transaction_id)
        end

        it "takes the event into account" do
          expect(event_store.sum).to eq(115) # New event value added to the previous one
        end
      end
    end
  end

  describe "#grouped_sum" do
    let(:grouped_by) { %w[region] }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the sum of values grouped by the provided group" do
      result = event_store.grouped_sum

      expect(result).to match_array([
        {groups: {"region" => nil}, value: 6},
        {groups: {"region" => "europe"}, value: 9}
      ])
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[region country] }

      it "returns the sum of values grouped by the provided groups" do
        result = event_store.grouped_sum

        expect(result).to match_array([
          {groups: {"country" => nil, "region" => nil}, value: 6},
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: 5},
          {groups: {"country" => "france", "region" => "europe"}, value: 4}
        ])
      end
    end

    context "with filters" do
      let(:matching_filters) { {"region" => ["europe"], "country" => ["france", "united kingdom"]} }
      let(:ignored_filters) { [{"city" => ["caen"]}, {"city" => ["cambridge", "london"], "country" => ["united kingdom"]}] }
      let(:grouped_by) { %w[region country] }

      before { create_events_for_filters }

      it "returns the sum filtered and grouped" do
        result = event_store.grouped_sum

        # We include:
        # - europe, france, <nil>
        # - europe, france, paris
        # - europe, france, caen
        # - europe, france, cambridge
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # - europe, united kingdom, manchester
        # Then exclude:
        # - europe, france, caen
        # - europe, united kingdom, cambridge
        # - europe, united kingdom, london
        # We should have 2 events:
        # - europe, france, <nil> -> 3
        # - europe, france, paris -> 1
        # - europe, france, cambridge -> -2
        # - europe, united kingdom, manchester -> -1
        expect(result).to match_array([
          {groups: {"country" => "united kingdom", "region" => "europe"}, value: -1},
          {groups: {"country" => "france", "region" => "europe"}, value: 2}
        ])
      end
    end
  end

  describe "#sum_date_breakdown" do
    it "returns the sum grouped by day" do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.sum_date_breakdown).to eq(
        events.map do |e|
          {
            date: e.timestamp.to_date,
            value: e.properties[billable_metric.field_name].to_i
          }
        end
      )
    end
  end

  describe "#prorated_events_values" do
    it "returns the values attached to each event with prorata on period duration" do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.prorated_events_values(31).map { |v| v.round(3) }).to eq(
        [0.516, 0.968, 1.355, 1.677, 1.935]
      )
    end
  end

  describe "#prorated_sum" do
    it "returns the prorated sum of event properties" do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.prorated_sum(period_duration: 31).round(5)).to eq(6.45161)
    end

    context "with persisted_duration" do
      it "returns the prorated sum of event properties" do
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        expect(event_store.prorated_sum(period_duration: 31, persisted_duration: 10).round(5)).to eq(4.83871)
      end
    end
  end

  describe "#grouped_prorated_sum" do
    let(:grouped_by) { %w[region] }

    it "returns the prorated sum of event properties" do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      result = event_store.grouped_prorated_sum(period_duration: 31)

      expect(result).to match_array([
        {groups: {"region" => nil}, value: within(0.00001).of(2.64516)},
        {groups: {"region" => "europe"}, value: within(0.00001).of(3.80645)}
      ])
    end

    context "with persisted_duration" do
      it "returns the prorated sum of event properties" do
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        result = event_store.grouped_prorated_sum(period_duration: 31, persisted_duration: 10)

        expect(result).to match_array([
          {groups: {"region" => nil}, value: within(0.00001).of(1.93548)},
          {groups: {"region" => "europe"}, value: within(0.00001).of(2.90322)}
        ])
      end
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[region country] }

      it "returns the sum of values grouped by the provided groups" do
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        result = event_store.grouped_prorated_sum(period_duration: 31)

        expect(result).to match_array(
          [
            {
              groups: {"country" => "united kingdom", "region" => "europe"},
              value: within(0.00001).of(1.93548)
            },
            {
              groups: {"country" => nil, "region" => nil},
              value: within(0.00001).of(2.64516)
            },
            {
              groups: {"country" => "france", "region" => "europe"},
              value: within(0.00001).of(1.87096)
            }
          ]
        )
      end
    end
  end

  describe "#weighted_sum" do
    let(:started_at) { Time.zone.parse("2023-03-01") }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 2},
        {timestamp: Time.zone.parse("2023-03-05 01:00:00"), value: 3},
        {timestamp: Time.zone.parse("2023-03-05 01:30:00"), value: 1},
        {timestamp: Time.zone.parse("2023-03-05 02:00:00"), value: -4},
        {timestamp: Time.zone.parse("2023-03-05 04:00:00"), value: -2},
        {timestamp: Time.zone.parse("2023-03-05 05:00:00"), value: 10},
        {timestamp: Time.zone.parse("2023-03-05 05:30:00"), value: -10}
      ]
    end

    let(:events) do
      events_values.map do |values|
        properties = {}
        properties[:region] = values[:region] if values[:region]

        create_event(
          value: values[:value],
          timestamp: values[:timestamp],
          properties:
        )
      end
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the weighted sum of event properties" do
      expect(event_store.weighted_sum.round(5)).to eq(0.02218)
    end

    context "with a single event" do
      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 1000}
        ]
      end

      it "returns the weighted sum of event properties" do
        expect(event_store.weighted_sum.round(5)).to eq(870.96774) # 4 / 31 * 0 + 27 / 31 * 1000
      end
    end

    context "with no events" do
      let(:events_values) { [] }

      it "returns the weighted sum of event properties" do
        expect(event_store.weighted_sum.round(5)).to eq(0.0)
      end
    end

    context "with events with the same timestamp" do
      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 3},
          {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 3}
        ]
      end

      it "returns the weighted sum of event properties" do
        expect(event_store.weighted_sum.round(5)).to eq(5.22581) # 4 / 31 * 0 + 27 / 31 * 6
      end
    end

    context "with initial value" do
      let(:initial_value) { 1000 }

      it "uses the initial value in the aggregation" do
        expect(event_store.weighted_sum(initial_value:).round(5)).to eq(1000.02218)
      end

      context "without events" do
        let(:events_values) { [] }

        it "uses only the initial value in the aggregation" do
          expect(event_store.weighted_sum(initial_value:).round(5)).to eq(1000.0)
        end
      end
    end

    context "with filters" do
      let(:matching_filters) { {region: ["europe"]} }

      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-03-04 00:00:00.000"), value: 1000, region: "us"},
          {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 1000, region: "europe"}
        ]
      end

      it "returns the weighted sum of event properties scoped to the group" do
        expect(event_store.weighted_sum.round(5)).to eq(870.96774) # 4 / 31 * 0 + 27 / 31 * 1000
      end
    end
  end

  describe "#weighted_sum_breakdown" do
    let(:started_at) { Time.zone.parse("2023-03-01") }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 2},
        {timestamp: Time.zone.parse("2023-03-05 01:00:00"), value: 3},
        {timestamp: Time.zone.parse("2023-03-05 01:30:00"), value: 1},
        {timestamp: Time.zone.parse("2023-03-05 02:00:00"), value: -4},
        {timestamp: Time.zone.parse("2023-03-05 04:00:00"), value: -2},
        {timestamp: Time.zone.parse("2023-03-05 05:00:00"), value: 10},
        {timestamp: Time.zone.parse("2023-03-05 05:30:00"), value: -10}
      ]
    end

    let(:events) do
      events_values.map do |values|
        properties = {}
        properties[:region] = values[:region] if values[:region]

        create_event(
          value: values[:value],
          timestamp: values[:timestamp],
          properties:
        )
      end
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the weighted sum of event properties" do
      expected_breakdown = [
        [format_timestamp("2023-03-01T00:00:00.000Z", precision: 5), 0.0, 0.0, 345600, 0.0],
        [format_timestamp("2023-03-05T00:00:00.000Z", precision: 5), 2, 2, 3600, within(0.00001).of(0.00268)],
        [format_timestamp("2023-03-05T01:00:00.000Z", precision: 5), 3, 5, 1800, within(0.00001).of(0.00336)],
        [format_timestamp("2023-03-05T01:30:00.000Z", precision: 5), 1, 6, 1800, within(0.00001).of(0.00403)],
        [format_timestamp("2023-03-05T02:00:00.000Z", precision: 5), -4, 2, 7200, within(0.00001).of(0.00537)],
        [format_timestamp("2023-03-05T04:00:00.000Z", precision: 5), -2, 0.0, 3600, 0.0],
        [format_timestamp("2023-03-05T05:00:00.000Z", precision: 5), 10, 10, 1800, within(0.00001).of(0.00672)],
        [format_timestamp("2023-03-05T05:30:00.000Z", precision: 5), -10, 0.0, 2313000, 0.0],
        [format_timestamp("2023-04-01T00:00:00.000Z", precision: 5), 0.0, 0.0, 0.0, 0.0]
      ]
      expect(event_store.weighted_sum_breakdown).to match(expected_breakdown)
    end

    context "with a single event" do
      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 1000}
        ]
      end

      it "returns the weighted sum of event properties" do
        expected_breakdown = [
          [format_timestamp("2023-03-01T00:00:00.000Z", precision: 5), 0.0, 0.0, 345600, 0.0],
          [format_timestamp("2023-03-05T00:00:00.000Z", precision: 5), 1000, 1000, 2332800, within(0.00001).of(870.96774)],
          [format_timestamp("2023-04-01T00:00:00.000Z", precision: 5), 0.0, 1000, 0.0, 0.0]
        ]
        expect(event_store.weighted_sum_breakdown).to match(expected_breakdown)
      end
    end

    context "with no events" do
      let(:events_values) { [] }

      it "returns the weighted sum of event properties" do
        expect(event_store.weighted_sum_breakdown).to match([
          [format_timestamp("2023-03-01T00:00:00.000Z", precision: 5), 0.0, 0.0, 2678400, 0.0],
          [format_timestamp("2023-04-01T00:00:00.000Z", precision: 5), 0.0, 0.0, 0.0, 0.0]
        ])
      end
    end

    context "with events with the same timestamp" do
      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 3},
          {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 3}
        ]
      end

      it "returns the weighted sum of event properties" do
        expected_breakdown = [
          [format_timestamp("2023-03-01T00:00:00.000Z", precision: 5), 0, 0, 345600, 0.0],
          [format_timestamp("2023-03-05T00:00:00.000Z", precision: 5), 3, 3, 0, 0.0],
          [format_timestamp("2023-03-05T00:00:00.000Z", precision: 5), 3, 6, 2332800, within(0.00001).of(5.22580)],
          [format_timestamp("2023-04-01T00:00:00.000Z", precision: 5), 0.0, 6, 0.0, 0.0]
        ]
        expect(event_store.weighted_sum_breakdown).to match(expected_breakdown)
      end
    end

    context "with initial value" do
      let(:initial_value) { 1000 }

      it "uses the initial value in the aggregation" do
        expected_breakdown = [
          [format_timestamp("2023-03-01T00:00:00.000Z", precision: 5), 1000, 1000, 345600, within(0.00001).of(129.03225)],
          [format_timestamp("2023-03-05T00:00:00.000Z", precision: 5), 2, 1002, 3600, within(0.00001).of(1.34677)],
          [format_timestamp("2023-03-05T01:00:00.000Z", precision: 5), 3, 1005, 1800, within(0.00001).of(0.67540)],
          [format_timestamp("2023-03-05T01:30:00.000Z", precision: 5), 1, 1006, 1800, within(0.00001).of(0.67607)],
          [format_timestamp("2023-03-05T02:00:00.000Z", precision: 5), -4, 1002, 7200, within(0.00001).of(2.69354)],
          [format_timestamp("2023-03-05T04:00:00.000Z", precision: 5), -2, 1000, 3600, within(0.00001).of(1.34408)],
          [format_timestamp("2023-03-05T05:00:00.000Z", precision: 5), 10, 1010, 1800, within(0.00001).of(0.67876)],
          [format_timestamp("2023-03-05T05:30:00.000Z", precision: 5), -10, 1000, 2313000, within(0.00001).of(863.57526)],
          [format_timestamp("2023-04-01T00:00:00.000Z", precision: 5), 0.0, 1000, 0.0, 0.0]
        ]
        expect(event_store.weighted_sum_breakdown(initial_value:)).to match(expected_breakdown)
      end

      context "without events" do
        let(:events_values) { [] }

        it "uses only the initial value in the aggregation" do
          expected_breakdown = [
            [format_timestamp("2023-03-01T00:00:00.000Z", precision: 5), 1000, 1000, 2678400, 1000],
            [format_timestamp("2023-04-01T00:00:00.000Z", precision: 5), 0.0, 1000, 0.0, 0.0]
          ]
          expect(event_store.weighted_sum_breakdown(initial_value:)).to match(expected_breakdown)
        end
      end
    end

    context "with filters" do
      let(:matching_filters) { {region: ["europe"]} }

      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-03-04 00:00:00.000"), value: 1000, region: "us"},
          {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 1000, region: "europe"}
        ]
      end

      it "returns the weighted sum of event properties scoped to the group" do
        expected_breakdown = [
          [format_timestamp("2023-03-01T00:00:00.000Z", precision: 5), 0, 0, 345600, 0.0],
          [format_timestamp("2023-03-05T00:00:00.000Z", precision: 5), 1000, 1000, 2332800, within(0.00001).of(870.96774)],
          [format_timestamp("2023-04-01T00:00:00.000Z", precision: 5), 0.0, 1000, 0.0, 0.0]
        ]
        expect(event_store.weighted_sum_breakdown).to match(expected_breakdown)
      end
    end
  end

  describe "#grouped_weighted_sum" do
    let(:grouped_by) { %w[agent_name other] }

    let(:started_at) { Time.zone.parse("2023-03-01") }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 2, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-03-05 01:00:00"), value: 3, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-03-05 01:30:00"), value: 1, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-03-05 02:00:00"), value: -4, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-03-05 04:00:00"), value: -2, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-03-05 05:00:00"), value: 10, agent_name: "frodo"},
        {timestamp: Time.zone.parse("2023-03-05 05:30:00"), value: -10, agent_name: "frodo"},

        {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 2, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-05 01:00:00"), value: 3, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-05 01:30:00"), value: 1, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-05 02:00:00"), value: -4, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-05 04:00:00"), value: -2, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-05 05:00:00"), value: 10, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-05 05:30:00"), value: -10, agent_name: "aragorn"},

        {timestamp: Time.zone.parse("2023-03-05 00:00:00.000"), value: 2},
        {timestamp: Time.zone.parse("2023-03-05 01:00:00"), value: 3},
        {timestamp: Time.zone.parse("2023-03-05 01:30:00"), value: 1},
        {timestamp: Time.zone.parse("2023-03-05 02:00:00"), value: -4},
        {timestamp: Time.zone.parse("2023-03-05 04:00:00"), value: -2},
        {timestamp: Time.zone.parse("2023-03-05 05:00:00"), value: 10},
        {timestamp: Time.zone.parse("2023-03-05 05:30:00"), value: -10}
      ]
    end

    let(:events) do
      events_values.map do |values|
        properties = {}
        properties[:region] = values[:region] if values[:region]
        properties[:agent_name] = values[:agent_name] if values[:agent_name]

        create_event(
          timestamp: values[:timestamp],
          value: values[:value],
          properties:
        )
      end
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the weighted sum of event properties" do
      result = event_store.grouped_weighted_sum

      expect(result.count).to eq(3)

      null_group = result.find { |v| v[:groups]["agent_name"].nil? }
      expect(null_group[:groups]["agent_name"]).to be_nil
      expect(null_group[:groups]["other"]).to be_nil
      expect(null_group[:value].round(5)).to eq(0.02218)

      (result - [null_group]).each do |row|
        expect(row[:groups]["agent_name"]).not_to be_nil
        expect(row[:groups]["other"]).to be_nil
        expect(row[:value].round(5)).to eq(0.02218)
      end
    end

    context "with no events" do
      let(:events_values) { [] }

      it "returns the weighted sum of event properties" do
        result = event_store.grouped_weighted_sum

        expect(result.count).to eq(0)
      end
    end

    context "with initial values" do
      let(:initial_values) do
        [
          {groups: {"agent_name" => "frodo", "other" => nil}, value: 1000},
          {groups: {"agent_name" => "aragorn", "other" => nil}, value: 1000},
          {groups: {"agent_name" => nil, "other" => nil}, value: 1000}
        ]
      end

      it "uses the initial value in the aggregation" do
        result = event_store.grouped_weighted_sum(initial_values:)

        expect(result.count).to eq(3)

        null_group = result.find { |v| v[:groups]["agent_name"].nil? }
        expect(null_group[:groups]["agent_name"]).to be_nil
        expect(null_group[:groups]["other"]).to be_nil
        expect(null_group[:value].round(5)).to eq(1000.02218)

        (result - [null_group]).each do |row|
          expect(row[:groups]["agent_name"]).not_to be_nil
          expect(row[:groups]["other"]).to be_nil
          expect(row[:value].round(5)).to eq(1000.02218)
        end
      end

      context "without events" do
        let(:events_values) { [] }

        it "uses only the initial value in the aggregation" do
          result = event_store.grouped_weighted_sum(initial_values:)

          expect(result.count).to eq(3)

          null_group = result.find { |v| v[:groups]["agent_name"].nil? }
          expect(null_group[:groups]["agent_name"]).to be_nil
          expect(null_group[:groups]["other"]).to be_nil
          expect(null_group[:value].round(5)).to eq(1000)

          (result - [null_group]).each do |row|
            expect(row[:groups]["agent_name"]).not_to be_nil
            expect(row[:groups]["other"]).to be_nil
            expect(row[:value].round(5)).to eq(1000)
          end
        end
      end
    end
  end
end
