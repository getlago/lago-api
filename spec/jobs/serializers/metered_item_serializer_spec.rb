# frozen_string_literal: true

require "rails_helper"

RSpec.describe Jobs::Serializers::MeteredItemSerializer do
  let(:organization) { create(:organization) }
  let(:event) { create(:event, organization:) }
  let(:charge) { create(:standard_charge, :pay_in_advance, organization:) }
  let(:charge_boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: event.timestamp,
      to_datetime: event.timestamp,
      charges_from_datetime: event.timestamp,
      charges_to_datetime: event.timestamp,
      charges_duration: 0,
      timestamp: event.timestamp
    )
  end
  let(:charge_metered_item) do
    Fees::ChargeService::MeteredItem.from_charge(
      charge:, boundaries: charge_boundaries, event: Events::CommonFactory.new_instance(source: event)
    )
  end

  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "amount", recurring: true) }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD", proration: true) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, rate_card:) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:, rate_model: "standard", rate_properties: {"amount" => "30"}) }
  let(:billing_segment) do
    create(
      :billing_segment,
      organization:,
      contract: contract_rate_card.contract,
      customer: contract_rate_card.contract.customer,
      contract_rate_card:,
      rate_card_rate:,
      currency: "USD",
      rate_properties: {"amount" => "20"},
      billing_at: Time.zone.parse("2026-10-01"),
      cycle_started_at: Time.zone.parse("2026-09-01"),
      started_at: Time.zone.parse("2026-09-01"),
      ended_at: Time.zone.parse("2026-09-30").end_of_day
    )
  end
  let(:billing_segment_metered_item) do
    Fees::ChargeService::MeteredItem.from_billing_segment(
      billing_segment, event: Events::CommonFactory.new_instance(source: event)
    )
  end
  let(:product_filter) { create(:product_filter, organization:, product:) }

  describe ".serialize?" do
    it "supports charge and billing segment metered items" do
      expect(described_class.serialize?(charge_metered_item)).to be(true)
      expect(described_class.serialize?(billing_segment_metered_item)).to be(true)
    end
  end

  describe "serialization" do
    it "serializes every charge source initializer attribute" do
      serialized = ActiveJob::Arguments.serialize([charge_metered_item]).first

      expect(serialized.keys).to include(*charge_metered_item.source.class.members.map(&:to_s))
    end

    it "serializes every billing segment source initializer attribute" do
      serialized = ActiveJob::Arguments.serialize([billing_segment_metered_item]).first

      expect(serialized.keys).to include(*billing_segment_metered_item.source.class.members.map(&:to_s))
    end

    it "serializes the charge source attributes and ignores billing segment attributes" do
      serialized = ActiveJob::Arguments.serialize([charge_metered_item]).first

      expect(serialized).to include(
        "source_type" => "charge",
        "charge" => anything,
        "boundaries" => anything,
        "charge_filter" => nil,
        "properties_override" => nil,
        "event" => anything
      )
      expect(serialized).not_to have_key("billing_segment")
      expect(serialized).not_to have_key("product_filter")
    end

    it "serializes the billing segment source attributes and ignores charge attributes" do
      serialized = ActiveJob::Arguments.serialize([billing_segment_metered_item]).first

      expect(serialized).to include(
        "source_type" => "billing_segment",
        "billing_segment" => anything,
        "product_filter" => nil,
        "event" => anything
      )
      expect(serialized).not_to have_key("charge")
      expect(serialized).not_to have_key("boundaries")
      expect(serialized).not_to have_key("charge_filter")
      expect(serialized).not_to have_key("properties_override")
    end

    it "round trips a charge source" do
      serialized = JSON.parse(ActiveJob::Arguments.serialize([charge_metered_item]).to_json).first
      deserialized = ActiveJob::Arguments.deserialize([serialized]).first

      expect(deserialized.source).to be_a(Fees::ChargeService::Sources::Charge)
      expect(deserialized.charge).to eq(charge)
      expect(deserialized.event.timestamp).to eq(event.timestamp)
      expect(deserialized.boundaries).to have_attributes(
        from_datetime: charge_boundaries.from_datetime,
        to_datetime: charge_boundaries.to_datetime,
        charges_from_datetime: charge_boundaries.charges_from_datetime,
        charges_to_datetime: charge_boundaries.charges_to_datetime,
        charges_duration: charge_boundaries.charges_duration,
        timestamp: charge_boundaries.timestamp
      )
    end

    it "round trips a billing segment source" do
      serialized = JSON.parse(ActiveJob::Arguments.serialize([billing_segment_metered_item]).to_json).first
      deserialized = ActiveJob::Arguments.deserialize([serialized]).first

      expect(deserialized.source).to be_a(Fees::ChargeService::Sources::BillingSegment)
      expect(deserialized.billing_segment).to eq(billing_segment)
      expect(deserialized.event.timestamp).to eq(event.timestamp)
    end

    it "preserves the selected billing segment product filter" do
      metered_item = billing_segment_metered_item.with_filter(product_filter)
      serialized = JSON.parse(ActiveJob::Arguments.serialize([metered_item]).to_json).first
      deserialized = ActiveJob::Arguments.deserialize([serialized]).first

      expect(deserialized.product_filter).to eq(product_filter)
    end

    it "rejects an unsupported source type" do
      serialized = ActiveJob::Arguments.serialize([charge_metered_item]).first
      serialized["source_type"] = "unknown"

      expect do
        ActiveJob::Arguments.deserialize([serialized])
      end.to raise_error(
        ActiveJob::DeserializationError,
        'Error while trying to deserialize arguments: Unsupported MeteredItem source type: "unknown"'
      )
    end
  end
end
