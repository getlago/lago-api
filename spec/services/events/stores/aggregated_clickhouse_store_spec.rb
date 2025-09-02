# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::AggregatedClickhouseStore, type: :service, clickhouse: true do
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

      if i.even?
        # matching_filters.each { |key, values| properties[key] = values.first }

        applied_grouped_by_values = grouped_by_values || with_grouped_by_values

        if applied_grouped_by_values.present?
          applied_grouped_by_values.each { |grouped_by, value| groups[grouped_by] = value }
        elsif grouped_by.present?
          grouped_by.each do |group|
            groups[group] = group_values[group.to_sym][i / 2]
          end
        end
      elsif grouped_by.present?
        grouped_by.each do |group|
          groups[group] = described_class::NIL_GROUP_VALUE
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
        charge_filter_id: charge_filter&.id || "",
        charge_filter_version: charge_filter&.updated_at || "",
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
end
