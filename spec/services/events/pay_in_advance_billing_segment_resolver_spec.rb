# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::PayInAdvanceBillingSegmentResolver do
  subject(:billing_segments) { described_class.call!(event:).billing_segments }

  let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:timezone) { "UTC" }
  let(:timestamp) { Time.zone.parse("2027-01-15 12:00:00") }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:contract_status) { :active }
  let(:contract) { create(:contract, organization:, customer:, status: contract_status) }
  let(:external_subscription_id) { contract.external_id }
  let(:event) do
    Events::Common.new(organization_id: organization.id, external_subscription_id:,
      timestamp:, code: billable_metric.code, properties: {})
  end
  let(:product_billable_metric) { billable_metric }
  let(:product) { create(:product, :metered, organization:, billable_metric: product_billable_metric) }
  let(:billing_timing) { :advance }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
  let(:effective_date) { Date.new(2027, 1, 1) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date:, billing_anchor_date: effective_date)
  end
  let(:rate_changed_at) { Time.zone.parse("2027-01-15 12:00:00") }
  let(:first_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"))
  end
  let(:second_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_changed_at,
      rate_properties: {"amount" => "20"})
  end

  before do
    contract_rate_card
    first_rate
    second_rate
  end

  it "builds the rate's covering slice without persisting a segment" do
    segment = billing_segments.sole

    expect(segment).to be_new_record
    expect(segment).to have_attributes(contract_rate_card:, rate_card_rate: second_rate,
      cycle_started_at: Time.zone.parse("2027-01-01"), started_at: rate_changed_at,
      ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-02-01")),
      rate_properties: second_rate.properties)
    expect(contract_rate_card.billing_segments.count).to eq(0)
  end

  it "preserves the segment snapshot across job serialization" do
    metered_item = Fees::ChargeService::MeteredItem.from_billing_segment(
      billing_segment: billing_segments.sole, event:
    )
    serialized = JSON.parse(ActiveJob::Arguments.serialize([metered_item]).to_json).first
    restored = ActiveJob::Arguments.deserialize([serialized]).sole

    expect(restored.billing_segment).to be_new_record
    expect(restored.billing_segment).to have_attributes(rate_card_rate: second_rate,
      started_at: rate_changed_at, ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-02-01")))
  end

  context "when two cards price the same metric" do
    let(:other_card) { create(:rate_card, organization:, product:, billing_timing: :advance) }
    let(:other_effective_date) { Date.new(2027, 1, 15) }
    let(:other_attachment) do
      create(:contract_rate_card, organization:, contract:, rate_card: other_card,
        effective_date: other_effective_date, billing_anchor_date: other_effective_date)
    end
    let(:other_rate) do
      create(:rate_card_rate, organization:, rate_card: other_card,
        effective_from: other_effective_date.in_time_zone(timezone))
    end

    before do
      other_attachment
      other_rate
    end

    it "selects only the latest effective attachment" do
      expect(billing_segments.sole.contract_rate_card).to eq(other_attachment)
    end

    context "when the later attachment is not yet effective" do
      let(:other_effective_date) { Date.new(2027, 1, 16) }

      it "selects the earlier attachment" do
        expect(billing_segments.sole.contract_rate_card).to eq(contract_rate_card)
      end
    end

    context "when the later attachment bills in arrears" do
      let(:other_card) { create(:rate_card, organization:, product:, billing_timing: :arrears) }

      it "returns no pay-in-advance segment after the replacement takes effect" do
        expect(billing_segments).to be_empty
      end

      context "when the event is exactly at the replacement's local effective date" do
        let(:timezone) { "America/New_York" }
        let(:timestamp) { other_effective_date.in_time_zone(timezone) }

        it "returns no pay-in-advance segment" do
          expect(billing_segments).to be_empty
        end

        context "when the event is just before the replacement takes effect" do
          let(:timestamp) { other_effective_date.in_time_zone(timezone) - 1.second }

          it "still selects the earlier advance attachment" do
            expect(billing_segments.sole.contract_rate_card).to eq(contract_rate_card)
          end
        end
      end
    end

    context "when the event falls between the second and third versions" do
      let(:other_effective_date) { Date.new(2027, 1, 10) }
      let(:future_card) { create(:rate_card, organization:, product:, billing_timing: :advance) }
      let(:future_attachment) do
        create(:contract_rate_card, organization:, contract:, rate_card: future_card,
          effective_date: Date.new(2027, 1, 16), billing_anchor_date: Date.new(2027, 1, 16))
      end

      before { future_attachment }

      it "selects the latest eligible version" do
        expect(billing_segments.sole.contract_rate_card).to eq(other_attachment)
      end
    end

    context "when the event is between September 22 and October 1" do
      let(:effective_date) { Date.new(2026, 9, 22) }
      let(:other_effective_date) { Date.new(2026, 10, 1) }
      let(:rate_changed_at) { Time.zone.parse("2026-09-25") }
      let(:timestamp) { Time.zone.parse("2026-09-30 12:00:00") }
      let(:first_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: effective_date.in_time_zone(timezone))
      end

      it "uses September 22's version, not the future October 1 version" do
        expect(billing_segments.sole).to have_attributes(contract_rate_card:, rate_card_rate: second_rate)
      end
    end
  end

  context "when two products share the billable metric" do
    let(:other_product) { create(:product, :metered, organization:, billable_metric:) }
    let(:other_card) { create(:rate_card, organization:, product: other_product, billing_timing: :advance) }
    let(:other_attachment) do
      create(:contract_rate_card, organization:, contract:, rate_card: other_card,
        effective_date:, billing_anchor_date: effective_date)
    end
    let(:other_rate) do
      create(:rate_card_rate, organization:, rate_card: other_card, effective_from: effective_date.in_time_zone(timezone))
    end

    before do
      other_attachment
      other_rate
    end

    it "returns a covering segment for each product at the same effective date" do
      expect(billing_segments.map(&:contract_rate_card)).to match_array([contract_rate_card, other_attachment])
      expect(billing_segments).to all(be_new_record)
    end

    it "loads pricing for the selected cards in batches" do
      queries = []
      subscriber = ->(_name, _started, _finished, _id, payload) { queries << payload[:sql] }

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { billing_segments }

      expect(queries.grep(/FROM "rate_card_rates"/).length).to eq(1)
      expect(queries.grep(/FROM "rate_phases"/).length).to eq(1)
    end

    context "when both cards use a pricing unit" do
      let(:pricing_unit) { create(:pricing_unit, organization:) }
      let(:rate_card) do
        create(:rate_card, organization:, product:, billing_timing:, applied_pricing_unit_code: pricing_unit.code)
      end
      let(:other_card) do
        create(:rate_card, organization:, product: other_product, billing_timing: :advance,
          applied_pricing_unit_code: pricing_unit.code)
      end
      let(:first_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
          applied_pricing_unit_conversion_rate: 2)
      end
      let(:second_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: rate_changed_at,
          applied_pricing_unit_conversion_rate: 3)
      end
      let(:other_rate) do
        create(:rate_card_rate, organization:, rate_card: other_card, effective_from: effective_date.in_time_zone(timezone),
          applied_pricing_unit_conversion_rate: 4)
      end

      it "fetches the shared pricing unit once" do
        queries = []
        subscriber = ->(_name, _started, _finished, _id, payload) { queries << payload[:sql] }

        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          expect(billing_segments.map(&:pricing_unit)).to eq([pricing_unit, pricing_unit])
        end

        expect(queries.grep(/FROM "pricing_units"/).length).to eq(1)
      end
    end

    it "creates a metered-item selection for each product" do
      selections = Events::PayInAdvanceMeteredItemsResolver.call!(event:).selections

      expect(selections.map { |selection| selection.metered_item.contract_rate_card })
        .to match_array([contract_rate_card, other_attachment])
    end

    context "when one product has a newer attachment version" do
      let(:newer_card) { create(:rate_card, organization:, product:, billing_timing: :advance) }
      let(:newer_attachment) do
        create(:contract_rate_card, organization:, contract:, rate_card: newer_card,
          effective_date: Date.new(2027, 1, 10), billing_anchor_date: Date.new(2027, 1, 10))
      end
      let(:newer_rate) do
        create(:rate_card_rate, organization:, rate_card: newer_card, effective_from: Time.zone.parse("2027-01-10"))
      end

      before do
        newer_attachment
        newer_rate
      end

      it "returns the latest version of that product alongside the other product" do
        expect(billing_segments.map(&:contract_rate_card)).to match_array([newer_attachment, other_attachment])
      end
    end
  end

  context "when cards for one product target different filter buckets" do
    let(:product_filter) { create(:product_filter, organization:, product:) }
    let(:filtered_card) do
      create(:rate_card, organization:, product:, product_filter:, billing_timing: :advance)
    end
    let(:filtered_attachment) do
      create(:contract_rate_card, organization:, contract:, rate_card: filtered_card,
        effective_date:, billing_anchor_date: effective_date)
    end
    let(:filtered_rate) do
      create(:rate_card_rate, organization:, rate_card: filtered_card,
        effective_from: effective_date.in_time_zone(timezone))
    end

    before do
      filtered_attachment
      filtered_rate
    end

    it "keeps both candidate buckets for product-filter matching" do
      expect(billing_segments.map(&:contract_rate_card)).to match_array([contract_rate_card, filtered_attachment])
    end
  end

  context "when a phase overrides the rate" do
    let(:rate_override) do
      create(:rate_override, organization:, rate_model: :standard, rate_properties: {"amount" => "30"})
    end

    before do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, rate_override:,
        billing_interval_cycle_count: 1)
    end

    it "uses the override's pricing snapshot" do
      expect(billing_segments.sole).to have_attributes(rate_card_rate: second_rate,
        rate_override:, rate_properties: rate_override.properties)
    end
  end

  context "when the card uses a pricing unit" do
    let(:rate_card) do
      create(:rate_card, organization:, product:, billing_timing:, applied_pricing_unit_code: pricing_unit.code)
    end
    let(:pricing_unit) { create(:pricing_unit, organization:) }
    let(:first_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
        applied_pricing_unit_conversion_rate: 2)
    end
    let(:second_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: rate_changed_at,
        applied_pricing_unit_conversion_rate: 3)
    end

    it "attaches the unit and new conversion rate" do
      segment = billing_segments.sole

      expect(segment.pricing_unit).to eq(pricing_unit)
      expect(segment.pricing_unit_conversion_rate).to eq(3)
    end
  end

  context "when a stored segment covers the old full cycle" do
    let(:stored_segment) do
      create(:billing_segment, organization:, customer:, contract:, contract_rate_card:,
        rate_card_rate: first_rate, cycle_started_at: effective_date.in_time_zone(timezone),
        started_at: effective_date.in_time_zone(timezone),
        ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-02-01")), status: :processing)
    end

    before { stored_segment }

    it "selects the new rate instead of the stored old one" do
      expect(billing_segments.sole).to have_attributes(rate_card_rate: second_rate,
        started_at: rate_changed_at)
    end

    context "when the stored segment is done" do
      let(:segment_status) { :done }

      before { stored_segment.update!(status: segment_status) }

      it "still prices the event from the schedule" do
        expect(billing_segments.sole.rate_card_rate).to eq(second_rate)
      end
    end
  end

  context "when the event precedes the rate change by half a millisecond" do
    let(:timestamp) { rate_changed_at - Rational(500, 1_000_000) }

    it "selects the first rate and its inclusive end" do
      expect(billing_segments.sole).to have_attributes(rate_card_rate: first_rate,
        ended_at: BillingSegment.inclusive_end(rate_changed_at))
    end
  end

  context "when the change starts between milliseconds" do
    let(:rate_changed_at) { Time.zone.parse("2027-01-15 12:00:00.123456") }
    let(:timestamp) { rate_changed_at - BillingSegment::MICROSECOND }

    it "keeps the old rate until the exact activation" do
      expect(billing_segments.sole.rate_card_rate).to eq(first_rate)
    end
  end

  context "when the rate changes at the next cycle boundary" do
    let(:rate_changed_at) { Time.zone.parse("2027-02-01") }
    let(:timestamp) { rate_changed_at }

    it "starts a fresh cycle with the second rate" do
      expect(billing_segments.sole).to have_attributes(rate_card_rate: second_rate,
        cycle_started_at: rate_changed_at, started_at: rate_changed_at)
    end
  end

  context "when the customer is in a different timezone" do
    let(:timezone) { "America/New_York" }
    let(:timestamp) { Time.zone.parse("2027-01-01 04:59:59") }

    it "does not select a card before its local effective date" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the customer inherits the billing entity's timezone" do
    let(:timezone) { nil }
    let(:billing_entity) { create(:billing_entity, organization:, timezone: "America/New_York") }
    let(:customer) { create(:customer, organization:, billing_entity:, timezone:) }
    let(:timestamp) { Time.zone.parse("2027-01-01 05:00:00") }

    it "selects the card at midnight in the inherited timezone" do
      expect(billing_segments.sole.contract_rate_card).to eq(contract_rate_card)
    end
  end

  context "when an active and a pending contract share the external id" do
    let(:timestamp) { Time.zone.parse("2027-01-01 05:00:00") }
    let(:other_customer) { create(:customer, organization:, timezone: "America/New_York") }
    let(:other_contract) do
      create(:contract, organization:, customer: other_customer, status: :pending, external_id: contract.external_id)
    end
    let(:other_attachment) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:,
        effective_date:, billing_anchor_date: effective_date)
    end

    before { other_attachment }

    it "selects only the active contract" do
      expect(billing_segments.sole.contract).to eq(contract)
    end
  end

  context "when the attachment takes effect after the event" do
    let(:effective_date) { Date.new(2027, 1, 16) }

    it "returns no segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when there is no effective rate yet" do
    let(:timestamp) { Time.zone.parse("2026-12-31 23:00:00") }

    it "returns no segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the product catalog is disabled" do
    let(:organization) { create(:organization) }

    it "returns no segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the contract is pending" do
    let(:contract_status) { :pending }

    it "returns no segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the contract is terminated" do
    let(:contract_status) { :terminated }

    it "returns no segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the external id does not match" do
    let(:external_subscription_id) { SecureRandom.uuid }

    it "returns no segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the rate card bills in arrears" do
    let(:billing_timing) { :arrears }

    it "returns no segment" do
      expect(billing_segments).to be_empty
    end
  end

  context "when the product has another metric" do
    let(:product_billable_metric) { create(:billable_metric, organization:) }

    it "returns no segment" do
      expect(billing_segments).to be_empty
    end
  end
end
