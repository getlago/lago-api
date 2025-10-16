# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::AggregatedClickhouseStore, clickhouse: true do
  group_values = {
    cloud: %w[aws azure gcp],
    region: %w[eu me us]
  }

  subject(:event_store) do
    described_class.new(
      code:,
      subscription:,
      boundaries:,
      filters: {
        grouped_by:,
        grouped_by_values:,
        charge_id:,
        charge_filter:,
        matching_filters:,
        ignored_filters:
      }
    )
  end

  let(:billable_metric) { create(:billable_metric, field_name: "value", code: "bm:code") }
  let(:aggregation_type) { "count" }
  let(:organization) { billable_metric.organization }

  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:, started_at:) }

  let(:started_at) { Time.zone.parse("2023-03-15") }
  let(:code) { billable_metric.code }

  let(:boundaries) do
    {
      from_datetime: subscription.started_at.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_duration: 31
    }
  end

  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:grouped_by) { nil }
  let(:grouped_by_values) { nil }
  let(:with_grouped_by_values) { nil }

  let(:charge_id) { charge.id }
  let(:charge_filter) { nil }
  let(:matching_filters) { {} }
  let(:ignored_filters) { [] }

  let(:events) do
    events = []

    5.times do |i|
      properties = {billable_metric.field_name => i + 1}
      groups = {}
      charge_filter_id = ""
      charge_filter_version = ""

      if i.even?
        applied_grouped_by_values = grouped_by_values || with_grouped_by_values

        if applied_grouped_by_values.present?
          applied_grouped_by_values.each { |grouped_by, value| groups[grouped_by] = value || described_class::NIL_GROUP_VALUE }
        elsif grouped_by.present?
          grouped_by.each do |group|
            groups[group] = group_values[group.to_sym][i / 2]
          end
        end
      else
        charge_filter_id = charge_filter&.id || ""
        charge_filter_version = charge_filter&.updated_at || ""

        if grouped_by.present?
          grouped_by.each do |group|
            groups[group] = described_class::NIL_GROUP_VALUE
          end
        end
      end

      (ignored_filters.first || {}).each { |key, values| properties[key] = values.first } if i.zero?

      events << Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: plan.id,
        code:,
        aggregation_type:,
        charge_id:,
        charge_version: charge.updated_at,
        charge_filter_id:,
        charge_filter_version:,
        timestamp: boundaries[:from_datetime] + (i + 1).days,
        properties:,
        value: (i + 1).to_s,
        decimal_value: (i + 1).to_d,
        precise_total_amount_cents: i + 1.1,
        grouped_by: groups
      )
    end

    events
  end

  # NOTE: this does not include test with real values yet as we have to figure out
  #       how to add factories of fixtures in spec env and to setup clickhouse on the CI
  before do
    if ENV["LAGO_CLICKHOUSE_ENABLED"].blank?
      skip
    else
      events
    end
  end

  after do
    next if ENV["LAGO_CLICKHOUSE_ENABLED"].blank?

    Clickhouse::BaseRecord.connection.execute("TRUNCATE TABLE events_enriched")
    Clickhouse::BaseRecord.connection.execute("TRUNCATE TABLE events_enriched_expanded")
    Clickhouse::BaseRecord.connection.execute("TRUNCATE TABLE events_aggregated")
  end

  describe ".events" do
    it "returns a list of events" do
      expect(event_store.events.count).to eq(5)
    end

    context "with grouped_by_values" do
      let(:grouped_by_values) { {"region" => "europe"} }

      it "returns a list of events" do
        expect(event_store.events.count).to eq(3)
      end

      context "when grouped_by_values value is nil" do
        let(:grouped_by_values) { {"region" => nil} }

        it "returns a list of events" do
          expect(event_store.events.count).to eq(3)
        end
      end
    end

    context "with filters" do
      let(:charge_filter) { create(:charge_filter, charge:) }

      it "returns a list of events" do
        expect(event_store.events.count).to eq(2) # 1st event is ignored
      end
    end
  end

  describe ".distinct_codes" do
    let(:other_event) do
      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: plan.id,
        code: "other_code",
        aggregation_type:,
        charge_id:,
        charge_version: charge.updated_at,
        timestamp: boundaries[:from_datetime] + 4.days,
        properties: {},
        value: 4.to_s,
        decimal_value: 4.to_d,
        precise_total_amount_cents: 4 + 1.1,
        grouped_by: {}
      )
    end

    let(:outside_boundaries_event) do
      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: plan.id,
        code: "outside_boundaries",
        aggregation_type:,
        charge_id:,
        charge_version: charge.updated_at,
        timestamp: boundaries[:from_datetime] - 4.days,
        properties: {},
        value: 4.to_s,
        decimal_value: 4.to_d,
        precise_total_amount_cents: 4 + 1.1,
        grouped_by: {}
      )
    end

    before { other_event }

    it "returns an array of distinct codes" do
      expect(event_store.distinct_codes).to match_array([billable_metric.code, "other_code"])
    end
  end

  describe ".distinct_charge_filter_ids" do
    it "returns an empty array of when no charge filters are present" do
      expect(event_store.distinct_charge_filter_ids).to be_empty
    end

    context "when charge filters are present" do
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:charge_filter2) { create(:charge_filter, charge:) }

      let(:other_event) do
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: charge_filter2.id,
          charge_filter_version: charge_filter2.updated_at,
          timestamp: boundaries[:from_datetime] + 4.days,
          properties: {},
          value: 4.to_s,
          decimal_value: 4.to_d,
          precise_total_amount_cents: 4 + 1.1,
          grouped_by: {}
        )
      end

      before { other_event }

      it "returns an array of distinct charge filter ids" do
        expect(event_store.distinct_charge_filter_ids).to match_array([charge_filter.id, charge_filter2.id])
      end
    end
  end

  describe ".events_values" do
    it "returns the value attached to each event" do
      expect(event_store.events_values).to eq([1, 2, 3, 4, 5])
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
            charge_id:,
            charge_filter:,
            matching_filters:,
            ignored_filters:,
            event:
          }
        )
      end

      let(:event) do
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type: "count",
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: charge_filter&.id,
          charge_filter_version: charge_filter&.updated_at,
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {billable_metric.field_name => 6},
          value: "6",
          decimal_value: 6,
          precise_total_amount_cents: 0,
          grouped_by: {}
        )
      end

      it "excludes current event but returns the value attached to other events" do
        event

        expect(event_store.events_values(exclude_event: true)).to eq([1, 2, 3, 4, 5])
      end
    end

    context "with a limit" do
      it "returns the value attached to each event" do
        expect(event_store.events_values(limit: 2)).to eq([1, 2])
      end
    end
  end

  describe ".prorated_events_values" do
    it "returns the values attached to each event with prorata on period duration" do
      expect(event_store.prorated_events_values(31).map { |v| v.round(3) }).to eq(
        [0.516, 0.968, 1.355, 1.677, 1.935]
      )
    end
  end

  describe ".last_event" do
    it "returns the last event" do
      expect(event_store.last_event.transaction_id).to eq(events.last.transaction_id)
    end
  end

  describe ".grouped_last_event" do
    let(:grouped_by) { %w[cloud] }

    it "returns the last events grouped by the provided group" do
      result = event_store.grouped_last_event

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]["cloud"].nil? }
      expect(null_group[:groups]["cloud"]).to be_nil
      expect(null_group[:value]).to eq(4)
      expect(null_group[:timestamp]).not_to be_nil

      result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
        next if row[:groups]["cloud"].nil?

        expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
        expect(row[:value]).not_to be_nil
        expect(row[:timestamp]).not_to be_nil
      end
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[cloud region] }

      it "returns the last events grouped by the provided groups" do
        result = event_store.grouped_last_event

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]["cloud"].nil? }
        expect(null_group[:groups]["cloud"]).to be_nil
        expect(null_group[:groups]["region"]).to be_nil
        expect(null_group[:value]).to eq(4)
        expect(null_group[:timestamp]).not_to be_nil

        result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
          next if row[:groups]["cloud"].nil?

          expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
          expect(row[:groups]["region"]).to eq(group_values[:region][index - 1])
          expect(row[:value]).not_to be_nil
          expect(row[:timestamp]).not_to be_nil
        end
      end
    end
  end

  describe ".count" do
    it "returns the number of unique events" do
      expect(event_store.count).to eq(5)
    end

    context "with grouped_by_values" do
      let(:grouped_by_values) { {"cloud" => "aws"} }

      it "returns the number of unique events matching the group" do
        expect(event_store.count).to eq(3)
      end
    end
  end

  describe ".grouped_count" do
    let(:grouped_by) { %w[cloud] }

    it "returns the number of unique events grouped by the provided group" do
      result = event_store.grouped_count

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]["cloud"].nil? }
      expect(null_group[:value]).to eq(2)

      result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
        next if row[:groups]["cloud"].nil?

        expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
        expect(row[:value]).to eq(1)
      end
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[region cloud] }

      it "returns the number of unique events grouped by the provided groups" do
        result = event_store.grouped_count

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]["cloud"].nil? }
        expect(null_group[:groups]["region"]).to be_nil
        expect(null_group[:value]).to eq(2)

        result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
          next if row[:groups]["cloud"].nil?

          expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
          expect(row[:groups]["region"]).to eq(group_values[:region][index - 1])
          expect(row[:value]).to eq(1)
        end
      end
    end
  end

  describe ".sum" do
    let(:aggregation_type) { "sum" }

    it "returns the sum of event properties" do
      expect(event_store.sum).to eq(15)
    end
  end

  describe ".grouped_sum" do
    let(:aggregation_type) { "sum" }
    let(:grouped_by) { %w[cloud] }

    it "returns the sum of values grouped by the provided group" do
      result = event_store.grouped_sum

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]["cloud"].nil? }
      expect(null_group[:value]).to eq(6)

      result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
        next if row[:groups]["cloud"].nil?

        expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
        expect(row[:value]).not_to be_nil
      end
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[cloud region] }

      it "returns the sum of values grouped by the provided groups" do
        result = event_store.grouped_sum

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]["cloud"].nil? }
        expect(null_group[:groups]["region"]).to be_nil
        expect(null_group[:value]).to eq(6)

        result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
          next if row[:groups]["cloud"].nil?

          expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
          expect(row[:groups]["region"]).to eq(group_values[:region][index - 1])
          expect(row[:value]).not_to be_nil
        end
      end
    end
  end

  describe "#sum_precise_total_amount_cents" do
    let(:aggregation_type) { "sum" }

    it "returns the sum of precise_total_amount_cent values" do
      expect(event_store.sum_precise_total_amount_cents).to eq(15.5)
    end
  end

  describe "#grouped_sum_precise_total_amount_cents" do
    let(:aggregation_type) { "sum" }
    let(:grouped_by) { %w[cloud] }

    it "returns the sum of values grouped by the provided group" do
      result = event_store.grouped_sum_precise_total_amount_cents

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]["cloud"].nil? }
      expect(null_group[:value]).to eq(6.2)

      result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
        next if row[:groups]["cloud"].nil?

        expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
        expect(row[:value]).not_to be_nil
      end
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[cloud region] }

      it "returns the sum of values grouped by the provided groups" do
        result = event_store.grouped_sum_precise_total_amount_cents

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]["cloud"].nil? }
        expect(null_group[:groups]["region"]).to be_nil
        expect(null_group[:value]).to eq(6.2)

        result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
          next if row[:groups]["cloud"].nil?

          expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
          expect(row[:groups]["region"]).to eq(group_values[:region][index - 1])
          expect(row[:value]).not_to be_nil
        end
      end
    end
  end

  describe ".prorated_sum" do
    it "returns the prorated sum of event properties" do
      expect(event_store.prorated_sum(period_duration: 31).round(5)).to eq(6.45161)
    end

    context "with persisted_duration" do
      it "returns the prorated sum of event properties" do
        expect(event_store.prorated_sum(period_duration: 31, persisted_duration: 10).round(5)).to eq(4.83871)
      end
    end
  end

  describe ".grouped_prorated_sum" do
    let(:grouped_by) { %w[cloud] }

    it "returns the prorated sum of event properties" do
      result = event_store.grouped_prorated_sum(period_duration: 31)

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]["cloud"].nil? }
      expect(null_group[:groups]["cloud"]).to be_nil
      expect(null_group[:value].round(5)).to eq(2.64516)

      result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
        next if row[:groups]["cloud"].nil?

        expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
        expect(row[:value]).not_to be_nil
      end
    end

    context "with persisted_duration" do
      it "returns the prorated sum of event properties" do
        result = event_store.grouped_prorated_sum(period_duration: 31, persisted_duration: 10)
        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]["cloud"].nil? }
        expect(null_group[:groups]["cloud"]).to be_nil
        expect(null_group[:value].round(5)).to eq(1.93548)

        result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
          next if row[:groups]["cloud"].nil?

          expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
          expect(row[:value]).not_to be_nil
        end
      end
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[cloud region] }

      it "returns the sum of values grouped by the provided groups" do
        result = event_store.grouped_prorated_sum(period_duration: 31)
        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]["cloud"].nil? }
        expect(null_group[:groups]["cloud"]).to be_nil
        expect(null_group[:groups]["region"]).to be_nil
        expect(null_group[:value].round(5)).to eq(2.64516)

        result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
          next if row[:groups]["cloud"].nil?

          expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
          expect(row[:groups]["region"]).to eq(group_values[:region][index - 1])
          expect(row[:value]).not_to be_nil
        end
      end
    end
  end

  describe ".sum_date_breakdown" do
    let(:aggregation_type) { "sum" }

    it "returns the sum grouped by day" do
      expect(event_store.sum_date_breakdown).to eq(
        events.map do |e|
          {
            date: e.timestamp.to_date,
            value: e.decimal_value
          }
        end
      )
    end
  end

  describe ".max" do
    let(:aggregation_type) { "max" }

    it "returns the max value" do
      expect(event_store.max).to eq(5)
    end
  end

  describe ".grouped_max" do
    let(:grouped_by) { %w[cloud] }
    let(:aggregation_type) { "max" }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the max values grouped by the provided group" do
      result = event_store.grouped_max

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]["cloud"].nil? }
      expect(null_group[:value]).to eq(4)

      result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
        next if row[:groups]["cloud"].nil?

        expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
        expect(row[:value]).not_to be_nil
      end
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[cloud region] }

      it "returns the max values grouped by the provided groups" do
        result = event_store.grouped_max

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]["cloud"].nil? }
        expect(null_group[:groups]["region"]).to be_nil
        expect(null_group[:value]).to eq(4)

        result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
          next if row[:groups]["cloud"].nil?

          expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
          expect(row[:groups]["region"]).to eq(group_values[:region][index - 1])
          expect(row[:value]).not_to be_nil
        end
      end
    end
  end

  describe ".last" do
    let(:aggregation_type) { "latest" }

    it "returns the last event" do
      expect(event_store.last).to eq(5)
    end
  end

  describe ".grouped_last" do
    let(:grouped_by) { %w[cloud] }
    let(:aggregation_type) { "latest" }

    it "returns the value attached to each event prorated on the provided duration" do
      result = event_store.grouped_last

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]["cloud"].nil? }
      expect(null_group[:value]).to eq(4)

      result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
        next if row[:groups]["cloud"].nil?

        expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
        expect(row[:value]).not_to be_nil
      end
    end

    context "with multiple groups" do
      let(:grouped_by) { %w[cloud region] }

      it "returns the last value for each provided groups" do
        result = event_store.grouped_last

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]["cloud"].nil? }
        expect(null_group[:groups]["region"]).to be_nil
        expect(null_group[:value]).to eq(4)

        result.sort_by { |it| it[:groups]["cloud"] || "" }.each_with_index do |row, index|
          next if row[:groups]["cloud"].nil?

          expect(row[:groups]["cloud"]).to eq(group_values[:cloud][index - 1])
          expect(row[:groups]["region"]).to eq(group_values[:region][index - 1])
          expect(row[:value]).not_to be_nil
        end
      end
    end
  end

  describe ".active_unique_property?" do
    before { event_store.aggregation_property = billable_metric.field_name }

    it "returns false when no previous events exist" do
      bm_value = SecureRandom.uuid

      event = ::Clickhouse::EventsEnrichedExpanded.create!(
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code:,
        timestamp: (boundaries[:from_datetime] + 2.days).end_of_day,
        properties: {
          billable_metric.field_name => bm_value
        },
        value: bm_value
      )

      expect(event_store).not_to be_active_unique_property(event)
    end

    context "when event is already active" do
      it "returns true if the event property is active" do
        ::Clickhouse::EventsEnrichedExpanded.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 2.days).end_of_day,
          properties: {
            billable_metric.field_name => 2
          },
          value: "2",
          decimal_value: 2
        )

        event = ::Clickhouse::EventsEnrichedExpanded.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 3.days).end_of_day,
          properties: {
            billable_metric.field_name => 2
          },
          value: "2",
          decimal_value: 2
        )

        expect(event_store).to be_active_unique_property(event)
      end
    end

    context "with a previous removed event" do
      it "returns false" do
        ::Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type: "unique_count",
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: charge_filter&.id,
          charge_filter_version: charge_filter&.updated_at,
          timestamp: (boundaries[:from_datetime] + 2.days).end_of_day,
          properties: {
            billable_metric.field_name => 2,
            :operation_type => "remove"
          },
          value: "2",
          decimal_value: 2
        )

        event = ::Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type: "unique_count",
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: charge_filter&.id,
          charge_filter_version: charge_filter&.updated_at,
          timestamp: (boundaries[:from_datetime] + 3.days).end_of_day,
          properties: {
            billable_metric.field_name => 2
          },
          value: "2",
          decimal_value: 2
        )

        expect(event_store).not_to be_active_unique_property(event)
      end
    end
  end

  describe "#unique_count" do
    it "returns the number of unique active event properties" do
      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: plan.id,
        code:,
        aggregation_type:,
        charge_id:,
        charge_version: charge.updated_at,
        charge_filter_id: "",
        charge_filter_version: "",
        timestamp: boundaries[:from_datetime] + 3.days,
        properties: {
          billable_metric.field_name => 2,
          :operation_type => "remove"
        },
        value: "2",
        decimal_value: 2.0,
        precise_total_amount_cents: 0,
        grouped_by: {}
      )

      event_store.aggregation_property = billable_metric.field_name

      expect(event_store.unique_count).to eq(4) # 5 events added / 1 removed
    end
  end

  describe "#prorated_unique_count" do
    it "returns the number of unique active event properties" do
      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: plan.id,
        code:,
        aggregation_type:,
        charge_id:,
        charge_version: charge.updated_at,
        charge_filter_id: "",
        charge_filter_version: "",
        timestamp: boundaries[:from_datetime] + 1.day,
        properties: {
          billable_metric.field_name => 2
        },
        value: "2",
        decimal_value: 2.0,
        precise_total_amount_cents: 0,
        grouped_by: {}
      )

      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: plan.id,
        code:,
        aggregation_type:,
        charge_id:,
        charge_version: charge.updated_at,
        charge_filter_id: "",
        charge_filter_version: "",
        timestamp: (boundaries[:from_datetime] + 1.day).end_of_day,
        properties: {
          billable_metric.field_name => 2,
          :operation_type => "remove"
        },
        value: "2",
        decimal_value: 2.0,
        precise_total_amount_cents: 0,
        grouped_by: {}
      )

      event_store.aggregation_property = billable_metric.field_name

      # NOTE: Events calculation: 16/31 + 1/31 + + 15/31 + 14/31 + 13/31 + 12/31
      expect(event_store.prorated_unique_count.round(3)).to eq(2.29)
    end
  end

  describe "#prorated_unique_count_breakdown" do
    it "returns the breakdown of add and remove of unique event properties" do
      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: plan.id,
        code:,
        aggregation_type:,
        charge_id:,
        charge_version: charge.updated_at,
        charge_filter_id: "",
        charge_filter_version: "",
        timestamp: boundaries[:from_datetime] + 1.day,
        properties: {
          billable_metric.field_name => 2
        },
        value: "2",
        decimal_value: 2.0,
        precise_total_amount_cents: 0,
        grouped_by: {}
      )

      Clickhouse::EventsEnrichedExpanded.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        subscription_id: subscription.id,
        plan_id: plan.id,
        code:,
        aggregation_type:,
        charge_id:,
        charge_version: charge.updated_at,
        charge_filter_id: "",
        charge_filter_version: "",
        timestamp: (boundaries[:from_datetime] + 1.day).end_of_day,
        properties: {
          billable_metric.field_name => 2,
          :operation_type => "remove"
        },
        value: "2",
        decimal_value: 2.0,
        precise_total_amount_cents: 0,
        grouped_by: {}
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

  describe "#grouped_unique_count" do
    let(:grouped_by) { %w[agent_name other] }
    let(:started_at) { Time.zone.parse("2023-03-01") }

    let(:events) do
      [
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: "",
          charge_filter_version: "",
          timestamp: boundaries[:from_datetime] + 1.hour,
          properties: {
            billable_metric.field_name => 2,
            "agent_name" => "frodo"
          },
          value: "2",
          decimal_value: 2.0,
          precise_total_amount_cents: 0,
          grouped_by: {agent_name: "frodo", other: described_class::NIL_GROUP_VALUE}
        ),
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: "",
          charge_filter_version: "",
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {
            billable_metric.field_name => 2,
            "agent_name" => "aragorn"
          },
          value: "2",
          decimal_value: 2.0,
          precise_total_amount_cents: 0,
          grouped_by: {agent_name: "aragorn", other: described_class::NIL_GROUP_VALUE}
        ),
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: "",
          charge_filter_version: "",
          timestamp: boundaries[:from_datetime] + 2.days,
          properties: {
            billable_metric.field_name => 2,
            "agent_name" => "aragorn",
            "operation_type" => "remove"
          },
          value: "2",
          decimal_value: 2.0,
          precise_total_amount_cents: 0,
          grouped_by: {agent_name: "aragorn", other: described_class::NIL_GROUP_VALUE}
        ),
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: "",
          charge_filter_version: "",
          timestamp: boundaries[:from_datetime] + 2.days,
          properties: {
            billable_metric.field_name => 2
          },
          value: "2",
          decimal_value: 2.0,
          precise_total_amount_cents: 0,
          grouped_by: {agent_name: described_class::NIL_GROUP_VALUE, other: described_class::NIL_GROUP_VALUE}
        )
      ]
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
    end

    it "returns the unique count of event properties" do
      result = event_store.grouped_unique_count

      expect(result.count).to eq(3)

      null_group = result.find { |v| v[:groups]["agent_name"].nil? }
      expect(null_group[:groups]["other"]).to be_nil
      expect(null_group[:value]).to eq(1)

      expect((result - [null_group]).map { |r| r[:value] }).to contain_exactly(1, 0)
    end

    context "with no events" do
      let(:events) { [] }

      it "returns the unique count of event properties" do
        result = event_store.grouped_unique_count
        expect(result.count).to eq(0)
      end
    end
  end

  describe "#grouped_prorated_unique_count" do
    let(:grouped_by) { %w[agent_name other] }
    let(:started_at) { Time.zone.parse("2023-03-01") }

    let(:events) do
      [
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: "",
          charge_filter_version: "",
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {
            billable_metric.field_name => 2,
            "agent_name" => "frodo"
          },
          value: "2",
          decimal_value: 2.0,
          precise_total_amount_cents: 0,
          grouped_by: {agent_name: "frodo", other: described_class::NIL_GROUP_VALUE}
        ),
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: "",
          charge_filter_version: "",
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {
            billable_metric.field_name => 2,
            "agent_name" => "aragorn"
          },
          value: "2",
          decimal_value: 2.0,
          precise_total_amount_cents: 0,
          grouped_by: {agent_name: "aragorn", other: described_class::NIL_GROUP_VALUE}
        ),
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: "",
          charge_filter_version: "",
          timestamp: (boundaries[:from_datetime] + 1.day).end_of_day,
          properties: {
            billable_metric.field_name => 2,
            "agent_name" => "aragorn",
            "operation_type" => "remove"
          },
          value: "2",
          decimal_value: 2.0,
          precise_total_amount_cents: 0,
          grouped_by: {agent_name: "aragorn", other: described_class::NIL_GROUP_VALUE}
        ),
        Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type:,
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: "",
          charge_filter_version: "",
          timestamp: boundaries[:from_datetime] + 2.days,
          properties: {
            billable_metric.field_name => 2
          },
          value: "2",
          decimal_value: 2.0,
          precise_total_amount_cents: 0,
          grouped_by: {agent_name: described_class::NIL_GROUP_VALUE, other: described_class::NIL_GROUP_VALUE}
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

  describe ".weighted_sum" do
    let(:started_at) { Time.zone.parse("2023-03-01") }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 2},
        {timestamp: Time.zone.parse("2023-03-01 01:00:00"), value: 3},
        {timestamp: Time.zone.parse("2023-03-01 01:30:00"), value: 1},
        {timestamp: Time.zone.parse("2023-03-01 02:00:00"), value: -4},
        {timestamp: Time.zone.parse("2023-03-01 04:00:00"), value: -2},
        {timestamp: Time.zone.parse("2023-03-01 05:00:00"), value: 10},
        {timestamp: Time.zone.parse("2023-03-01 05:30:00"), value: -10}
      ]
    end

    let(:events) do
      events_values.map do |values|
        ::Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type: "unique_count",
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: charge_filter&.id,
          charge_filter_version: charge_filter&.updated_at,
          timestamp: values[:timestamp],
          properties: {},
          value: values[:value].to_s,
          decimal_value: values[:value].to_d,
          grouped_by: {}
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
          {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 1000}
        ]
      end

      it "returns the weighted sum of event properties" do
        expect(event_store.weighted_sum.round(5)).to eq(1000.0)
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
          {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 3},
          {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 3}
        ]
      end

      it "returns the weighted sum of event properties" do
        expect(event_store.weighted_sum.round(5)).to eq(6.0)
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
      let(:charge_filter) { create(:charge_filter, charge:) }

      let(:events_values) do
        [
          {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 1000, region: "europe"}
        ]
      end

      it "returns the weighted sum of event properties scoped to the group" do
        expect(event_store.weighted_sum.round(5)).to eq(1000.0)
      end
    end
  end

  describe ".weighted_sum_breakdown" do
    let(:started_at) { Time.zone.parse("2023-03-01") }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 2},
        {timestamp: Time.zone.parse("2023-03-01 01:00:00"), value: 3},
        {timestamp: Time.zone.parse("2023-03-01 01:30:00"), value: 1},
        {timestamp: Time.zone.parse("2023-03-01 02:00:00"), value: -4},
        {timestamp: Time.zone.parse("2023-03-01 04:00:00"), value: -2},
        {timestamp: Time.zone.parse("2023-03-01 05:00:00"), value: 10},
        {timestamp: Time.zone.parse("2023-03-01 05:30:00"), value: -10}
      ]
    end

    let(:events) do
      events_values.map do |values|
        ::Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type: "unique_count",
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: charge_filter&.id,
          charge_filter_version: charge_filter&.updated_at,
          timestamp: values[:timestamp],
          properties: {},
          value: values[:value].to_s,
          decimal_value: values[:value].to_d,
          grouped_by: {}
        )
      end
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it "returns the weighted sum of event properties" do
      breakdown = event_store.weighted_sum_breakdown

      expect(breakdown.count).to eq(9) # 7 events + initial and final states
      # Fiels: Timestamp, Event value, Continuous sum, duration in second, prorated values on the period
      expect(breakdown[0]).to eq(["2023-03-01 00:00:00.00000", 0, 0, 0, 0])
      expect(breakdown[1]).to eq(["2023-03-01 00:00:00.00000", 2, 2, 3600, BigDecimal("0.00268817204301075268817204")])
      expect(breakdown[2]).to eq(["2023-03-01 01:00:00.00000", 3, 5, 1800, BigDecimal("0.00336021505376344086021505")])
      expect(breakdown[3]).to eq(["2023-03-01 01:30:00.00000", 1, 6, 1800, BigDecimal("0.00403225806451612903225806")])
      expect(breakdown[4]).to eq(["2023-03-01 02:00:00.00000", -4, 2, 7200, BigDecimal("0.00537634408602150537634408")])
      expect(breakdown[5]).to eq(["2023-03-01 04:00:00.00000", -2, 0, 3600, 0])
      expect(breakdown[6]).to eq(["2023-03-01 05:00:00.00000", 10, 10, 1800, BigDecimal("0.0067204301075268817204301")])
      expect(breakdown[7]).to eq(["2023-03-01 05:30:00.00000", -10, 0, 2658600, 0])
      expect(breakdown[8]).to eq(["2023-04-01 00:00:00.00000", 0, 0, 0, 0])
    end
  end

  describe ".grouped_weighted_sum" do
    let(:grouped_by) { %w[agent_name other] }

    let(:started_at) { Time.zone.parse("2023-03-01") }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 2, agent_name: "frodo'"},
        {timestamp: Time.zone.parse("2023-03-01 01:00:00"), value: 3, agent_name: "frodo'"},
        {timestamp: Time.zone.parse("2023-03-01 01:30:00"), value: 1, agent_name: "frodo'"},
        {timestamp: Time.zone.parse("2023-03-01 02:00:00"), value: -4, agent_name: "frodo'"},
        {timestamp: Time.zone.parse("2023-03-01 04:00:00"), value: -2, agent_name: "frodo'"},
        {timestamp: Time.zone.parse("2023-03-01 05:00:00"), value: 10, agent_name: "frodo'"},
        {timestamp: Time.zone.parse("2023-03-01 05:30:00"), value: -10, agent_name: "frodo'"},

        {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 2, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-01 01:00:00"), value: 3, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-01 01:30:00"), value: 1, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-01 02:00:00"), value: -4, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-01 04:00:00"), value: -2, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-01 05:00:00"), value: 10, agent_name: "aragorn"},
        {timestamp: Time.zone.parse("2023-03-01 05:30:00"), value: -10, agent_name: "aragorn"},

        {timestamp: Time.zone.parse("2023-03-01 00:00:00.000"), value: 2},
        {timestamp: Time.zone.parse("2023-03-01 01:00:00"), value: 3},
        {timestamp: Time.zone.parse("2023-03-01 01:30:00"), value: 1},
        {timestamp: Time.zone.parse("2023-03-01 02:00:00"), value: -4},
        {timestamp: Time.zone.parse("2023-03-01 04:00:00"), value: -2},
        {timestamp: Time.zone.parse("2023-03-01 05:00:00"), value: 10},
        {timestamp: Time.zone.parse("2023-03-01 05:30:00"), value: -10}
      ]
    end

    let(:events) do
      events_values.map do |values|
        ::Clickhouse::EventsEnrichedExpanded.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          subscription_id: subscription.id,
          plan_id: plan.id,
          code:,
          aggregation_type: "unique_count",
          charge_id:,
          charge_version: charge.updated_at,
          charge_filter_id: charge_filter&.id,
          charge_filter_version: charge_filter&.updated_at,
          timestamp: values[:timestamp],
          properties: {},
          value: values[:value].to_s,
          decimal_value: values[:value].to_d,
          grouped_by: {
            "agent_name" => values[:agent_name] || described_class::NIL_GROUP_VALUE,
            "other" => described_class::NIL_GROUP_VALUE
          }
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
          {groups: {"agent_name" => "frodo'", "other" => nil}, value: 1000},
          {groups: {"agent_name" => "aragorn", "other" => nil}, value: 2000},
          {groups: {"agent_name" => nil, "other" => nil}, value: 3000}
        ]
      end

      it "uses the initial value in the aggregation" do
        result = event_store.grouped_weighted_sum(initial_values:)

        expect(result.count).to eq(3)

        null_group = result.find { |v| v[:groups]["agent_name"].nil? }
        expect(null_group[:groups]["agent_name"]).to be_nil
        expect(null_group[:groups]["other"]).to be_nil
        expect(null_group[:value].round(5)).to eq(3000.02218)

        frodo_group = result.find { |v| v[:groups]["agent_name"] == "frodo'" }
        expect(frodo_group[:groups]["other"]).to be_nil
        expect(frodo_group[:value].round(5)).to eq(1000.02218)

        aragorn_group = result.find { |v| v[:groups]["agent_name"] == "aragorn" }
        expect(aragorn_group[:groups]["other"]).to be_nil
        expect(aragorn_group[:value].round(5)).to eq(2000.02218)
      end

      context "without events" do
        let(:events_values) { [] }

        it "uses only the initial value in the aggregation" do
          result = event_store.grouped_weighted_sum(initial_values:)

          expect(result.count).to eq(3)

          null_group = result.find { |v| v[:groups]["agent_name"].nil? }
          expect(null_group[:groups]["agent_name"]).to be_nil
          expect(null_group[:groups]["other"]).to be_nil
          expect(null_group[:value].round(5)).to eq(3000)

          frodo_group = result.find { |v| v[:groups]["agent_name"] == "frodo'" }
          expect(frodo_group[:groups]["other"]).to be_nil
          expect(frodo_group[:value].round(5)).to eq(1000)

          aragorn_group = result.find { |v| v[:groups]["agent_name"] == "aragorn" }
          expect(aragorn_group[:groups]["other"]).to be_nil
          expect(aragorn_group[:value].round(5)).to eq(2000)
        end
      end
    end
  end
end
