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
    end
  end
end
