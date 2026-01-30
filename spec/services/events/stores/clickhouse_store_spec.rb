# frozen_string_literal: true

require "rails_helper"

require_relative "shared_examples/an_event_store"

RSpec.describe Events::Stores::ClickhouseStore, clickhouse: true do
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
      precise_total_amount_cents: value,
      enriched_at: Time.current
    )
  end

  def format_timestamp(timestamp, precision: 3)
    Time.zone.parse(timestamp).strftime("%Y-%m-%d %H:%M:%S.%#{precision}L")
  end

  # Force ClickHouse to merge parts and ensure data consistency.
  # ReplacingMergeTree tables may have timing inconsistencies where data parts
  # aren't fully visible yet when queries run. OPTIMIZE FINAL forces synchronization.
  def force_sync
    Clickhouse::EventsEnriched.connection.execute("OPTIMIZE TABLE events_enriched FINAL")
  end

  context "without deduplication" do
    it_behaves_like "an event store", with_event_duplication: false do
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
            timestamp: boundaries[:from_datetime] + 1.day,
            properties: {
              billable_metric.field_name => 3
            },
            value: "30",
            decimal_value: 30
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
          expect(result.count).to eq(7)

          # Ensure consistent ordering with 2 events with the same timestamp
          expect(result.map { it["property"] }).to eq(%w[1 2 30 2 3 4 5])

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
    end
  end

  context "with deduplication" do
    it_behaves_like "an event store" do
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
            timestamp: boundaries[:from_datetime] + 1.day,
            properties: {
              billable_metric.field_name => 3
            },
            value: "30",
            decimal_value: 30
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
          expect(result.count).to eq(7)

          # Ensure consistent ordering with 2 events with the same timestamp
          expect(result.map { it["property"] }).to eq(%w[1 2 30 2 3 4 5])

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

      describe "#distinct_charges_and_filters" do
        let(:charge) { create(:standard_charge, organization:, billable_metric:) }
        let(:charge_filter) { create(:charge_filter, charge:) }

        before do
          Clickhouse::EventsEnrichedExpanded.create!(
            transaction_id: SecureRandom.uuid,
            organization_id: organization.id,
            external_subscription_id: subscription.external_id,
            subscription_id: subscription.id,
            plan_id: subscription.plan_id,
            code:,
            aggregation_type: billable_metric.aggregation_type,
            charge_id: charge.id,
            charge_version: charge.updated_at,
            charge_filter_id: charge_filter&.id,
            charge_filter_version: charge_filter&.updated_at,
            timestamp: boundaries[:from_datetime] + 12.days,
            properties: {},
            value: "12",
            decimal_value: 12.0,
            precise_total_amount_cents: nil
          )
        end

        it "returns the distinct event codes" do
          expect(event_store.distinct_charges_and_filters).to match_array([[charge.id, charge_filter.id]])
        end

        context "when charge_filter is nil" do
          let(:charge_filter) { nil }

          it "returns the distinct event codes" do
            expect(event_store.distinct_charges_and_filters).to match_array([[charge.id, ""]])
          end
        end
      end
    end
  end
end
