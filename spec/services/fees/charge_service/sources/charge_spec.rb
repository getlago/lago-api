# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ChargeService::Sources::Charge do
  subject(:source) { described_class.new(charge:, boundaries:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric:,
      properties: {amount: "20", free_units_per_events: "2", free_units_per_total_aggregation: "3"}
    )
  end
  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: Time.zone.parse("2022-03-01"),
      to_datetime: Time.zone.parse("2022-03-31").end_of_day,
      charges_from_datetime: Time.zone.parse("2022-03-01"),
      charges_to_datetime: Time.zone.parse("2022-03-31").end_of_day,
      charges_duration: 31,
      timestamp: Time.zone.parse("2022-04-01")
    )
  end

  describe "fee identity" do
    it "exposes charge fee attributes individually" do
      expect(source).to have_attributes(fee_type: :charge, invoiceable: charge)
    end
  end

  describe "#with_filter" do
    let(:charge_filter) { create(:charge_filter, charge:, properties: {amount: "30"}) }

    it "returns a source with the selected filter" do
      filtered_source = source.with_filter(charge_filter)

      expect(filtered_source.charge).to eq(charge)
      expect(filtered_source.boundaries).to eq(boundaries)
      expect(filtered_source.charge_filter).to eq(charge_filter)
      expect(filtered_source.properties).to eq(charge_filter.properties)
      expect(filtered_source.selected_filter).to eq(charge_filter)
    end

    it "clears the selected filter" do
      filtered_source = source.with_filter(charge_filter)

      expect(filtered_source.with_filter(nil)).to have_attributes(selected_filter: nil, properties: charge.properties)
    end
  end

  describe "#matching_and_ignored_filters" do
    it "memoizes the result per source without sharing it with a new filter source" do
      allow(Events::BillingPeriodFilters::MatchingAndIgnoredService).to receive(:call).and_return(BaseResult.new)

      result = source.matching_and_ignored_filters

      expect(source.matching_and_ignored_filters).to equal(result)
      expect(Events::BillingPeriodFilters::MatchingAndIgnoredService).to have_received(:call).once

      source.with_filter(nil).matching_and_ignored_filters

      expect(Events::BillingPeriodFilters::MatchingAndIgnoredService).to have_received(:call).twice
    end
  end

  describe "#properties" do
    it "uses explicit properties before filter and charge properties" do
      charge_filter = create(:charge_filter, charge:, properties: {amount: "30"})

      expect(source.properties).to eq(charge.properties)
      expect(source.with_filter(charge_filter).properties).to eq(charge_filter.properties)
      expect(source.with_filter(charge_filter, properties: {amount: "40"}).properties).to eq({amount: "40"})
    end
  end

  describe "#pricing_buckets" do
    let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: ["us"]) }
    let(:charge_filter) { create(:charge_filter, charge:) }
    let(:charge_filter_value) do
      create(
        :charge_filter_value,
        values: ["us"],
        billable_metric_filter: region,
        charge_filter:
      )
    end
    let(:event) { create(:event, organization:, properties: event_properties) }
    let(:event_properties) { {"region" => "us"} }

    before { charge_filter_value }

    it "returns only the filter matching the event" do
      buckets = source.pricing_buckets(event:)

      expect(buckets).to match([have_attributes(charge_filter:)])
    end

    context "when the event does not match any filter" do
      let(:event_properties) { {"region" => "eu"} }

      it "returns the default bucket with configured filter exclusions" do
        matching_event = create(:event, organization:, properties: {"region" => "us"})
        matching_bucket = source.pricing_buckets(event: matching_event).sole
        default_bucket = source.pricing_buckets(event:).sole

        expect(matching_bucket.charge_filter).to eq(charge_filter)
        expect(default_bucket).to have_attributes(
          charge_filter: have_attributes(charge:),
          properties: charge.properties
        )
        expect(default_bucket.matching_and_ignored_filters.ignored_filters).not_to be_empty
      end
    end
  end

  describe "#elapsed_period_ratio" do
    around { |test| travel_to(Time.zone.parse("2022-03-16")) { test.run } }

    it "returns the elapsed charge period ratio" do
      expect(source.elapsed_period_ratio).to eq(16.fdiv(31))
    end
  end

  describe "#pricing_group_keys" do
    it "returns pricing_group_keys properties" do
      charge.update!(properties: charge.properties.merge("pricing_group_keys" => ["region"]))

      expect(source.pricing_group_keys).to eq(["region"])
    end

    it "returns legacy grouped_by properties" do
      charge.update!(properties: charge.properties.merge("grouped_by" => ["region"]))

      expect(source.pricing_group_keys).to eq(["region"])
    end

    it "prefers pricing_group_keys over legacy grouped_by properties" do
      charge.update!(properties: charge.properties.merge("pricing_group_keys" => ["region"], "grouped_by" => ["cloud"]))

      expect(source.pricing_group_keys).to eq(["region"])
    end
  end
end
