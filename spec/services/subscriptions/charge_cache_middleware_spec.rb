# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ChargeCacheMiddleware, cache: :redis do
  subject(:middleware) { described_class.new(subscription:, charge:, to_datetime:, cache:) }

  let(:organization) { create(:organization, premium_integrations: zero_amount_fees_enabled ? ["zero_amount_fees"] : []) }
  let(:billing_entity) { organization.billing_entities.first }
  let(:zero_amount_fees_enabled) { false }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, plan:, organization:) }
  let(:charge) { create(:standard_charge, plan: plan, organization:) }
  let(:pricing_unit) { create(:pricing_unit, organization:, short_name: "CAR") }
  let(:to_datetime) { Time.current + 1.hour }
  let(:cache) { true }
  let(:charge_filter) { nil }
  let(:cache_key) do
    [
      "charge-usage",
      1,
      charge.id,
      subscription.id,
      charge.updated_at.iso8601,
      charge_filter&.id,
      charge_filter&.updated_at&.iso8601
    ].compact.join("/")
  end
  let(:invoice_display_name) { nil }
  let(:grouped_by) { {} }

  def fee(amount_cents:, with_pricing_unit_usage: false)
    build(:charge_fee,
      amount_cents:,
      amount_currency: "USD",
      fee_type: "charge",
      pricing_unit_usage: with_pricing_unit_usage ? PricingUnitUsage.new(
        organization: organization,
        pricing_unit:,
        short_name: "CAR",
        conversion_rate: 1.5,
        amount_cents: 150,
        precise_amount_cents: 150.0,
        unit_amount_cents: 10,
        precise_unit_amount: 10.0
      ) : nil,
      charge: charge,
      charge_filter: charge_filter,
      organization: organization,
      billing_entity: billing_entity,
      subscription: subscription,
      invoice_display_name:,
      grouped_by:)
  end

  def cached_fee_payload(amount_cents:, overrides: {})
    {
      "amount_cents" => amount_cents,
      "amount_currency" => "USD",
      "amount_details" => {},
      "fee_type" => "charge",
      "charge_id" => charge.id,
      "organization_id" => organization.id,
      "subscription_id" => subscription.id,
      "billing_entity_id" => billing_entity.id,
      "invoiceable_id" => charge.id,
      "invoiceable_type" => "Charge",
      "grouped_by" => {},
      "events_count" => 1,
      "payment_status" => "pending",
      "precise_amount_cents" => "200.0000000001",
      "precise_coupons_amount_cents" => "0.0",
      "precise_credit_notes_amount_cents" => "0.0",
      "precise_unit_amount" => "0.0",
      "pay_in_advance" => false,
      "properties" => {"charges_from_datetime" => "2022-08-01",
                       "charges_to_datetime" => "2022-08-31",
                       "from_datetime" => "2022-08-01",
                       "timestamp" => "2022-08-01",
                       "to_datetime" => "2022-08-31"},
      "taxes_base_rate" => 1.0,
      "taxes_precise_amount_cents" => "2.0000000001",
      "taxes_rate" => 0.0,
      "total_aggregated_units" => "0.0",
      "taxes_amount_cents" => 2,
      "unit_amount_cents" => 0,
      "units" => "0.0",
      **(charge_filter ? {"charge_filter_id" => charge_filter.id} : {})
    }.merge(overrides)
  end

  def charge_cache_key
    "charge-usage/1/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}"
  end

  def charge_filter_cache_key
    "charge-usage/1/#{charge.id}/#{subscription.id}/#{charge.updated_at.iso8601}/#{charge_filter.id}/#{charge_filter.updated_at.iso8601}"
  end

  def fetch_cache(key)
    value = Rails.cache.read(key)
    return nil if value.nil?

    JSON.parse(value)
  end

  def expire_time(key)
    Rails.cache.redis.with { |r| r.pexpiretime(key).to_f / 1000 }
  end

  # We have to compare attributes as ActiveRecord compares objects by their id
  def expect_to_match_fees(actual, expected)
    expect(actual).to all(be_a(Fee))
    expect(expected).to all(be_a(Fee))

    expect(actual.map(&:attributes)).to eq(expected.map(&:attributes))
  end

  describe "COMPACTABLE_PROPERTIES" do
    it "lists all fee properties keys that can be safely compacted" do
      # These are keys inside the `properties` jsonb column that are only set for fixed charge fees.
      # For regular charge fees they are nil and can be safely stripped.
      # If a new optional property key is added to fee properties, add it here if it can safely
      # default to nil when missing.
      expect(described_class::COMPACTABLE_PROPERTIES).to eq(Set.new(%w[
        fixed_charges_duration
        fixed_charges_from_datetime
        fixed_charges_to_datetime
      ]))
    end
  end

  describe "COMPACTABLE_ATTRIBUTES" do
    it "covers all Fee columns that can be safely compacted" do
      all_fee_columns = Set.new(Fee.column_names)
      compactable = described_class::COMPACTABLE_ATTRIBUTES
      non_compactable = all_fee_columns - compactable

      # Every attribute in COMPACTABLE_ATTRIBUTES must be a real Fee column (except pricing_unit_usage which is virtual)
      expect(compactable - all_fee_columns).to eq(Set.new(["pricing_unit_usage"]))

      # Non-compactable attributes are those whose nil value carries meaning or that should always be present.
      # If a new column is added to fees, this test will fail — add it to COMPACTABLE_ATTRIBUTES if it can
      # safely default to nil when missing, or add it to this list if it must always be present.
      expect(non_compactable).to eq(Set.new(%w[
        amount_cents
        amount_currency
        amount_details
        billing_entity_id
        charge_id
        events_count
        fee_type
        grouped_by
        invoiceable_id
        invoiceable_type
        organization_id
        payment_status
        precise_amount_cents
        precise_coupons_amount_cents
        precise_credit_notes_amount_cents
        precise_unit_amount
        properties
        subscription_id
        taxes_amount_cents
        taxes_base_rate
        taxes_precise_amount_cents
        taxes_rate
        total_aggregated_units
        unit_amount_cents
        units
      ]))
    end
  end

  describe "COMPACTABLE_PRICING_UNIT_USAGE_ATTRIBUTES" do
    it "covers all PricingUnitUsage columns that can be safely compacted" do
      all_columns = Set.new(PricingUnitUsage.column_names)
      compactable = described_class::COMPACTABLE_PRICING_UNIT_USAGE_ATTRIBUTES
      non_compactable = all_columns - compactable

      # Every attribute in COMPACTABLE_PRICING_UNIT_USAGE_ATTRIBUTES must be a real PricingUnitUsage column
      expect(compactable - all_columns).to be_empty

      # Non-compactable attributes carry pricing data that must always be present.
      # If a new column is added to pricing_unit_usages, this test will fail — add it to
      # COMPACTABLE_PRICING_UNIT_USAGE_ATTRIBUTES if it can safely default to nil when missing,
      # or add it to this list if it must always be present.
      expect(non_compactable).to eq(Set.new(%w[
        amount_cents
        conversion_rate
        organization_id
        precise_amount_cents
        precise_unit_amount
        pricing_unit_id
        short_name
        unit_amount_cents
      ]))
    end
  end

  describe "#call" do
    let(:fees) { [fee(amount_cents: 100), fee(amount_cents: 200)] }
    let(:other_fees) { [fee(amount_cents: 300)] }

    context "when cache is disabled" do
      let(:cache) { false }

      it "yields and returns the block result without caching" do
        result = middleware.call(charge_filter:) { fees }
        expect_to_match_fees(result, fees)

        result = middleware.call(charge_filter:) { other_fees }
        expect_to_match_fees(result, other_fees)

        expect(fetch_cache(charge_cache_key)).to be_nil
      end
    end

    context "when cache is enabled" do
      it "caches and returns the fees" do
        result = middleware.call(charge_filter:) { fees }

        expect_to_match_fees(result, fees)

        expect(fetch_cache(charge_cache_key)).to eq([
          cached_fee_payload(amount_cents: 100),
          cached_fee_payload(amount_cents: 200)
        ])
        key_expire_time = expire_time(charge_cache_key)
        expect(key_expire_time).to be_within(10.seconds).of(to_datetime.to_i)

        result = middleware.call(charge_filter:) { other_fees }
        expect_to_match_fees(result, fees)

        expect(fetch_cache(charge_cache_key)).to eq([
          cached_fee_payload(amount_cents: 100),
          cached_fee_payload(amount_cents: 200)
        ])
        # Key expire time should not be updated
        expect(expire_time(charge_cache_key)).to eq(key_expire_time)
      end

      context "with a charge filter" do
        let(:charge_filter) { create(:charge_filter) }

        it "passes the charge filter to the cache service" do
          result = middleware.call(charge_filter:) { fees }

          expect_to_match_fees(result, fees)

          expect(fetch_cache(charge_filter_cache_key)).to eq([
            cached_fee_payload(amount_cents: 100),
            cached_fee_payload(amount_cents: 200)
          ])

          result = middleware.call(charge_filter:) { other_fees }
          expect_to_match_fees(result, fees)

          expect(fetch_cache(charge_filter_cache_key)).to eq([
            cached_fee_payload(amount_cents: 100),
            cached_fee_payload(amount_cents: 200)
          ])
        end
      end

      context "with extra attributes" do
        let(:invoice_display_name) { "Invoice Display Name" }
        let(:grouped_by) { {"key_1" => "value_1", "key_2" => nil} }

        it "caches and reconstructs fees with extra attributes" do
          result = middleware.call(charge_filter:) { fees }
          expect_to_match_fees(result, fees)

          overrides = {"invoice_display_name" => "Invoice Display Name", "grouped_by" => {"key_1" => "value_1", "key_2" => nil}}
          expect(fetch_cache(charge_cache_key)).to eq([
            cached_fee_payload(amount_cents: 100, overrides:),
            cached_fee_payload(amount_cents: 200, overrides:)
          ])
        end
      end

      context "with pricing unit usage" do
        let(:fees) { [fee(amount_cents: 100, with_pricing_unit_usage: true)] }

        it "caches and reconstructs fees with pricing unit usage" do
          result = middleware.call(charge_filter:) { fees }
          expect_to_match_fees(result, fees)

          expect(fetch_cache(charge_cache_key)).to eq([
            cached_fee_payload(
              amount_cents: 100,
              overrides: {"pricing_unit_usage" => {
                "amount_cents" => 150,
                "conversion_rate" => "1.5",
                "organization_id" => organization.id,
                "precise_amount_cents" => "150.0",
                "precise_unit_amount" => "10.0",
                "pricing_unit_id" => pricing_unit.id,
                "short_name" => "CAR",
                "unit_amount_cents" => 10
              }}
            )
          ])

          result = middleware.call(charge_filter:) { other_fees }
          expect_to_match_fees(result, fees)

          expect(fetch_cache(charge_cache_key)).to eq([
            cached_fee_payload(
              amount_cents: 100,
              overrides: {"pricing_unit_usage" => {
                "amount_cents" => 150,
                "conversion_rate" => "1.5",
                "organization_id" => organization.id,
                "precise_amount_cents" => "150.0",
                "precise_unit_amount" => "10.0",
                "pricing_unit_id" => pricing_unit.id,
                "short_name" => "CAR",
                "unit_amount_cents" => 10
              }}
            )
          ])
        end
      end

      context "with all compactable attributes set to non-nil values" do
        let(:fee_id) { SecureRandom.uuid }
        let(:invoice_id) { SecureRandom.uuid }
        let(:add_on_id) { SecureRandom.uuid }
        let(:applied_add_on_id) { SecureRandom.uuid }
        let(:group_id) { SecureRandom.uuid }
        let(:fixed_charge_id) { SecureRandom.uuid }
        let(:true_up_parent_fee_id) { SecureRandom.uuid }
        let(:pay_in_advance_event_id) { SecureRandom.uuid }
        # Use a rounded time to avoid subsecond precision loss through JSON serialization
        let(:now) { Time.zone.parse("2026-01-15T10:00:00Z") }

        let(:fees) do
          [build(:charge_fee,
            id: fee_id,
            amount_cents: 100,
            amount_currency: "USD",
            fee_type: "charge",
            charge:,
            charge_filter:,
            organization:,
            billing_entity:,
            subscription:,
            invoice_display_name: "My Display Name",
            grouped_by: {"region" => "us", "provider" => nil},
            description: "A fee description",
            pay_in_advance: true,
            pay_in_advance_event_id:,
            pay_in_advance_event_transaction_id: "txn_123",
            invoice_id:,
            add_on_id:,
            applied_add_on_id:,
            group_id:,
            fixed_charge_id:,
            true_up_parent_fee_id:,
            succeeded_at: now,
            failed_at: now,
            refunded_at: now,
            deleted_at: now,
            created_at: now,
            updated_at: now)]
        end

        it "preserves all non-nil compactable attributes through the cache round-trip" do
          result = middleware.call(charge_filter:) { fees }
          expect_to_match_fees(result, fees)

          cached = fetch_cache(charge_cache_key)
          cached_fee = cached.first

          # All compactable attributes should be present (not compacted) when non-nil
          expect(cached_fee["id"]).to eq(fee_id)
          expect(cached_fee["invoice_display_name"]).to eq("My Display Name")
          expect(cached_fee["description"]).to eq("A fee description")
          expect(cached_fee["pay_in_advance"]).to be(true)
          expect(cached_fee["pay_in_advance_event_id"]).to eq(pay_in_advance_event_id)
          expect(cached_fee["pay_in_advance_event_transaction_id"]).to eq("txn_123")
          expect(cached_fee["invoice_id"]).to eq(invoice_id)
          expect(cached_fee["add_on_id"]).to eq(add_on_id)
          expect(cached_fee["applied_add_on_id"]).to eq(applied_add_on_id)
          expect(cached_fee["group_id"]).to eq(group_id)
          expect(cached_fee["fixed_charge_id"]).to eq(fixed_charge_id)
          expect(cached_fee["true_up_parent_fee_id"]).to eq(true_up_parent_fee_id)
          expect(cached_fee["succeeded_at"]).to be_present
          expect(cached_fee["failed_at"]).to be_present
          expect(cached_fee["refunded_at"]).to be_present
          expect(cached_fee["deleted_at"]).to be_present
          expect(cached_fee["created_at"]).to be_present
          expect(cached_fee["updated_at"]).to be_present
          expect(cached_fee["grouped_by"]).to eq({"region" => "us", "provider" => nil})

          # Verify cache hit returns the same fees
          result = middleware.call(charge_filter:) { other_fees }
          expect_to_match_fees(result, fees)
        end
      end

      context "with fixed charge properties" do
        let(:fees) do
          [build(:charge_fee,
            amount_cents: 100,
            amount_currency: "USD",
            fee_type: "charge",
            charge:,
            charge_filter:,
            organization:,
            billing_entity:,
            subscription:,
            properties: {
              "timestamp" => "2022-08-01",
              "from_datetime" => "2022-08-01",
              "to_datetime" => "2022-08-31",
              "charges_from_datetime" => "2022-08-01",
              "charges_to_datetime" => "2022-08-31",
              "fixed_charges_duration" => 30,
              "fixed_charges_from_datetime" => "2022-07-01",
              "fixed_charges_to_datetime" => "2022-07-31"
            })]
        end

        it "preserves fixed charge properties through the cache round-trip" do
          result = middleware.call(charge_filter:) { fees }
          expect_to_match_fees(result, fees)

          cached = fetch_cache(charge_cache_key)
          props = cached.first["properties"]

          expect(props["fixed_charges_duration"]).to eq(30)
          expect(props["fixed_charges_from_datetime"]).to eq("2022-07-01")
          expect(props["fixed_charges_to_datetime"]).to eq("2022-07-31")

          # Verify cache hit returns the same fees
          result = middleware.call(charge_filter:) { other_fees }
          expect_to_match_fees(result, fees)
        end
      end

      context "with nil fixed charge properties" do
        let(:fees) do
          [build(:charge_fee,
            amount_cents: 100,
            amount_currency: "USD",
            fee_type: "charge",
            charge:,
            charge_filter:,
            organization:,
            billing_entity:,
            subscription:,
            properties: {
              "timestamp" => "2022-08-01",
              "from_datetime" => "2022-08-01",
              "to_datetime" => "2022-08-31",
              "charges_from_datetime" => "2022-08-01",
              "charges_to_datetime" => "2022-08-31",
              "fixed_charges_duration" => nil,
              "fixed_charges_from_datetime" => nil,
              "fixed_charges_to_datetime" => nil
            })]
        end

        it "compacts nil fixed charge properties and reconstructs equivalent fees" do
          result = middleware.call(charge_filter:) { fees }

          cached = fetch_cache(charge_cache_key)
          props = cached.first["properties"]

          # Nil fixed charge properties should be compacted
          expect(props).not_to have_key("fixed_charges_duration")
          expect(props).not_to have_key("fixed_charges_from_datetime")
          expect(props).not_to have_key("fixed_charges_to_datetime")

          # Reconstructed fee properties should still return nil for these keys
          reconstructed_fee = result.first
          expect(reconstructed_fee.properties["fixed_charges_duration"]).to be_nil
          expect(reconstructed_fee.properties["fixed_charges_from_datetime"]).to be_nil
          expect(reconstructed_fee.properties["fixed_charges_to_datetime"]).to be_nil
        end
      end
    end
  end
end
