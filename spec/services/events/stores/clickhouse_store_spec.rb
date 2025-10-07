# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::ClickhouseStore, clickhouse: {clean_before: true} do
  it_behaves_like "an event store" do
    def create_event(timestamp:, value:, properties: {}, transaction_id: SecureRandom.uuid, code: billable_metric.code)
      Clickhouse::EventsEnriched.create!(
        transaction_id: transaction_id,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code:,
        timestamp: timestamp,
        properties: properties.merge(billable_metric.field_name => value).compact,
        value: value,
        decimal_value: value&.to_i&.to_d,
        precise_total_amount_cents: value
      )
    end

    def format_timestamp(timestamp)
      Time.zone.parse(timestamp).strftime("%Y-%m-%d %H:%M:%S.%L")
    end

    def force_deduplication
      Clickhouse::EventsEnriched.connection.execute("OPTIMIZE TABLE events_enriched FINAL")
    end

    describe "#prorated_unique_count" do
      it "returns the number of unique active event properties" do
        Clickhouse::EventsEnriched.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 0.days,
          properties: {
            billable_metric.field_name => 2
          },
          value: "2",
          decimal_value: 2
        )

        Clickhouse::EventsEnriched.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 0.days).end_of_day,
          properties: {
            billable_metric.field_name => 2,
            :operation_type => "remove"
          },
          value: "2",
          decimal_value: 2
        )
        event_store.aggregation_property = billable_metric.field_name

        # NOTE: Events calculation: 16/31 + 1/31 + + 15/31 + 14/31 + 13/31 + 12/31
        # Events:
        # 1 => added on 0 day, never removed => 16/31
        # 2 => added on 0 day, removed on 0 day => 1/31
        # 2 => added on 1 day, never removed => 15/31
        # 3 => added on 2 day, never removed => 14/31
        # 4 => added on 3 day, never removed => 13/31
        # 5 => added on 4 day, never removed => 12/31
        expect(event_store.prorated_unique_count.round(3)).to eq(2.29)
      end

      context "with multiple events at the same day" do
        it "returns the number of unique active event properties merged within one day" do
          event_params = [
            {timestamp: boundaries[:from_datetime], operation_type: "remove"},
            {timestamp: boundaries[:from_datetime] + 1.hour, operation_type: "add"},
            {timestamp: boundaries[:from_datetime] + 2.hours, operation_type: "remove"},
            {timestamp: boundaries[:from_datetime] + 3.hours, operation_type: "add"},
            {timestamp: boundaries[:from_datetime] + 1.day, operation_type: "remove"},
            {timestamp: boundaries[:from_datetime] + 1.day + 1.hour, operation_type: "add"},
            {timestamp: boundaries[:from_datetime] + 2.days + 1.hour, operation_type: "remove"}
          ]

          event_params.each do |params|
            Clickhouse::EventsEnriched.create!(
              transaction_id: SecureRandom.uuid,
              organization_id: organization.id,
              external_subscription_id: subscription.external_id,
              code:,
              timestamp: params[:timestamp],
              properties: {
                billable_metric.field_name => 2,
                :operation_type => params[:operation_type]
              },
              value: "2",
              decimal_value: 2
            )
          end

          # NOTE: Events calculation: 3/31
          # Events:
          # 1 => added on 0 day, never removed => 16/31
          # 2 => added on 0 day, removed on 2 day => 3/31
          # 3 => added on 2 day, never removed => 14/31
          # 4 => added on 3 day, never removed => 13/31
          # 5 => added on 4 day, never removed => 12/31
          expect(event_store.prorated_unique_count.round(3)).to eq(1.871) # 16/31 + 3/31 + 14/31 + 13/31 + 12/31
        end
      end
    end

    describe "#grouped_prorated_unique_count" do
      let(:grouped_by) { %w[agent_name other] }
      let(:started_at) { Time.zone.parse("2023-03-01") }

      let(:events) do
        [
          Clickhouse::EventsEnriched.create!(
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code:,
            transaction_id: SecureRandom.uuid,
            timestamp: boundaries[:from_datetime] + 1.day,
            properties: {
              billable_metric.field_name => 2,
              :agent_name => "frodo"
            },
            value: "2",
            decimal_value: 2
          ),
          Clickhouse::EventsEnriched.create!(
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code:,
            transaction_id: SecureRandom.uuid,
            timestamp: boundaries[:from_datetime] + 1.day,
            properties: {
              billable_metric.field_name => 2,
              :agent_name => "aragorn"
            },
            value: "2",
            decimal_value: 2
          ),
          Clickhouse::EventsEnriched.create!(
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code:,
            transaction_id: SecureRandom.uuid,
            timestamp: (boundaries[:from_datetime] + 1.day).end_of_day,
            properties: {
              billable_metric.field_name => 2,
              :agent_name => "aragorn",
              :operation_type => "remove"
            },
            value: "2",
            decimal_value: 2
          ),
          Clickhouse::EventsEnriched.create!(
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code:,
            transaction_id: SecureRandom.uuid,
            timestamp: boundaries[:from_datetime] + 2.days,
            properties: {billable_metric.field_name => 2},
            value: "2",
            decimal_value: 2
          )
        ]
      end

      before do
        event_store.aggregation_property = billable_metric.field_name
      end

      it "returns the unique count of event properties" do
        result = event_store.grouped_prorated_unique_count

        expect(result.count).to eq(3)

        null_group = result.find { |v| v[:groups]["agent_name"].nil? }
        expect(null_group[:groups]["other"]).to be_nil
        expect(null_group[:value].round(3)).to eq(0.935) # 29/31

        # NOTE: Events calculation: [1/31, 30/31]
        expect((result - [null_group]).map { |r| r[:value].round(3) }).to contain_exactly(0.032, 0.968)
      end

      context "with no events" do
        let(:events) { [] }

        it "returns the unique count of event properties" do
          result = event_store.grouped_prorated_unique_count
          expect(result.count).to eq(0)
        end
      end
    end

    describe "#prorated_unique_count_breakdown" do
      it "returns the breakdown of add and remove of unique event properties" do
        Clickhouse::EventsEnriched.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {
            billable_metric.field_name => 2
          },
          value: "2",
          decimal_value: 2
        )

        Clickhouse::EventsEnriched.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 1.day).end_of_day,
          properties: {
            billable_metric.field_name => 2,
            :operation_type => "remove"
          },
          value: "2",
          decimal_value: 2
        )

        event_store.aggregation_property = billable_metric.field_name

        result = event_store.prorated_unique_count_breakdown
        expect(result.count).to eq(6)

        grouped_result = result.group_by { |r| r["property"] }

        # NOTE: group with property 1
        group = grouped_result["1"]
        expect(group.count).to eq(1)
        expect(group.first["prorated_value"].round(3)).to eq(0.516) # 16/31
        expect(group.first["operation_type"]).to eq("add")

        # NOTE: group with property 2 (added and removed)
        group = grouped_result["2"]
        expect(group.first["prorated_value"].round(3)).to eq(0.032) # 1/31
        expect(group.last["prorated_value"].round(3)).to eq(0.484) # 15/31
        expect(group.count).to eq(2)

        # NOTE: group with property 3
        group = grouped_result["3"]
        expect(group.count).to eq(1)
        expect(group.first["prorated_value"].round(3)).to eq(0.452) # 14/31
        expect(group.first["operation_type"]).to eq("add")

        # NOTE: group with property 4
        group = grouped_result["4"]
        expect(group.count).to eq(1)
        expect(group.first["prorated_value"].round(3)).to eq(0.419) # 13/31
        expect(group.first["operation_type"]).to eq("add")

        # NOTE: group with property 5
        group = grouped_result["5"]
        expect(group.count).to eq(1)
        expect(group.first["prorated_value"].round(3)).to eq(0.387) # 12/31
        expect(group.first["operation_type"]).to eq("add")
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
          properties = {value: values[:value]}
          properties[:region] = values[:region] if values[:region]

          Clickhouse::EventsEnriched.create!(
            transaction_id: SecureRandom.uuid,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code:,
            timestamp: values[:timestamp],
            properties:,
            value: values[:value].to_s,
            decimal_value: values[:value].to_d
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
          properties = {value: values[:value]}
          properties[:region] = values[:region] if values[:region]
          properties[:agent_name] = values[:agent_name] if values[:agent_name]

          Clickhouse::EventsEnriched.create!(
            transaction_id: SecureRandom.uuid,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            code:,
            timestamp: values[:timestamp],
            properties:,
            value: values[:value].to_s,
            decimal_value: values[:value].to_d
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
end
