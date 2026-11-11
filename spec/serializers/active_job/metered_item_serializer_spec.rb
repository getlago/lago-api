# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActiveJob::MeteredItemSerializer do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
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
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:, rate_model: "standard", rate_properties: {"amount" => "30"}) }
  let(:billing_segment) do
    build(
      :billing_segment,
      organization:,
      contract:,
      customer:,
      contract_rate_card:,
      rate_card_rate:,
      currency: "USD",
      rate_properties: {"amount" => "20"},
      billing_at: Time.zone.parse("2026-10-01"),
      cycle_started_at: Time.zone.parse("2026-09-01"),
      started_at: Time.zone.parse("2026-09-01"),
      ended_at: Time.zone.parse("2026-09-30").end_of_day,
      proration_ratio: BigDecimal("0.3750000000")
    )
  end
  let(:billing_segment_metered_item) do
    Fees::ChargeService::MeteredItem.from_billing_segment(
      billing_segment:, event: Events::CommonFactory.new_instance(source: event)
    )
  end
  let(:billing_segment_max_timestamp) { Time.zone.parse("2026-09-15 12:34:56") }
  let(:billing_segment_metered_item_with_max_timestamp) do
    Fees::ChargeService::MeteredItem.from_billing_segment(
      billing_segment:,
      max_timestamp: billing_segment_max_timestamp,
      event: Events::CommonFactory.new_instance(source: event)
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
        "billing_segment" => a_hash_including(
          "rate_card_rate_id" => rate_card_rate.id,
          "billable_metric_code" => billable_metric.code,
          "rate_properties" => a_hash_including("amount" => "20"),
          "started_at" => anything,
          "ended_at" => anything
        ),
        "product_filter" => nil,
        "max_timestamp" => nil,
        "event" => anything
      )
      expect(serialized["billing_segment"]).not_to have_key("id")
      expect(serialized["billing_segment"]).not_to have_key("_aj_globalid")
      expect(serialized["billing_segment"]).not_to have_key("created_at")
      expect(serialized["billing_segment"]).not_to have_key("updated_at")
      expect(serialized["billing_segment"]).not_to have_key("invoice_id")
      expect(serialized["billing_segment"]).not_to have_key("contract_rate_card_billing_operation_id")
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
      expect(deserialized.billing_segment).not_to respond_to(:persisted?)
      expect(deserialized.billing_segment.attributes).to eq(billing_segment.attributes)
      expect(deserialized.billing_segment.started_at).to be_a(Time)
      expect(deserialized.billing_segment.proration_ratio).to be_a(BigDecimal)
      expect(deserialized.billing_segment.billable_metric_code).to eq(billable_metric.code)
      expect(deserialized.billing_segment.billing_at).to eq(billing_segment.billing_at)
      expect(deserialized.billing_segment.contract_rate_card).to eq(contract_rate_card)
      expect(deserialized.billing_segment.rate_card_rate).to eq(rate_card_rate)
      expect(deserialized.event.timestamp).to eq(event.timestamp)
    end

    it "accepts queued payloads that omit optional association ids" do
      serialized = JSON.parse(ActiveJob::Arguments.serialize([billing_segment_metered_item]).to_json).first
      %w[rate_override_id pricing_unit_id].each do |key|
        serialized.dig("billing_segment").delete(key)
      end

      deserialized = ActiveJob::Arguments.deserialize([serialized]).first

      expect(deserialized.billing_segment).to have_attributes(
        rate_card_rate:,
        rate_override: nil,
        pricing_unit: nil
      )
    end

    it "ignores deleted attribution keys in previously queued payloads" do
      serialized = JSON.parse(ActiveJob::Arguments.serialize([billing_segment_metered_item]).to_json).first
      serialized.dig("billing_segment").merge!(
        "invoice_id" => SecureRandom.uuid,
        "contract_rate_card_billing_operation_id" => SecureRandom.uuid
      )

      deserialized = ActiveJob::Arguments.deserialize([serialized]).first

      expect(deserialized.billing_segment).not_to respond_to(:invoice_id, :contract_rate_card_billing_operation_id, :invoice)
      expect(deserialized.billing_segment.attributes).not_to include("invoice_id", "contract_rate_card_billing_operation_id")
    end

    it "backfills the billable metric code for queued payloads that predate the captured code" do
      serialized = JSON.parse(ActiveJob::Arguments.serialize([billing_segment_metered_item]).to_json).first
      serialized.dig("billing_segment").delete("billable_metric_code")

      deserialized = ActiveJob::Arguments.deserialize([serialized]).first

      expect(deserialized.billing_segment.billable_metric_code).to eq(billable_metric.code)
    end

    it "does not hydrate references from a different organization" do
      serialized = JSON.parse(ActiveJob::Arguments.serialize([billing_segment_metered_item]).to_json).first
      serialized.dig("billing_segment")["organization_id"] = other_organization.id

      expect { ActiveJob::Arguments.deserialize([serialized]) }
        .to raise_error(ActiveJob::DeserializationError)
    end

    it "round trips the billing segment max timestamp" do
      serialized = JSON.parse(ActiveJob::Arguments.serialize([billing_segment_metered_item_with_max_timestamp]).to_json).first
      deserialized = ActiveJob::Arguments.deserialize([serialized]).first

      expect(deserialized.source.max_timestamp).to eq(billing_segment_max_timestamp)
    end

    it "deserializes a billing segment job without a max timestamp" do
      serialized = ActiveJob::Arguments.serialize([billing_segment_metered_item]).first
      serialized.delete("max_timestamp")

      deserialized = ActiveJob::Arguments.deserialize([serialized]).first

      expect(deserialized.source.max_timestamp).to be_nil
    end

    context "when the in-memory segment changes after the job is queued" do
      subject(:deserialized) { ActiveJob::Arguments.deserialize([serialized]).first }

      let(:serialized) { JSON.parse(ActiveJob::Arguments.serialize([billing_segment_metered_item]).to_json).first }
      let(:original_ended_at) { billing_segment.ended_at }

      before do
        original_ended_at
        serialized
        billing_segment.rate_properties = {"amount" => "99"}
        billing_segment.ended_at += 1.day
      end

      it "uses the rate and service period captured when the segment was built" do
        expect(deserialized.billing_segment).not_to respond_to(:persisted?)
        expect(deserialized.billing_segment.rate_properties).to eq("amount" => "20")
        expect(deserialized.billing_segment.ended_at).to eq(original_ended_at)
        expect(deserialized.billing_segment.rate_card_rate).to eq(rate_card_rate)
      end
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
