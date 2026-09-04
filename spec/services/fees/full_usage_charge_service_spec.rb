# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::FullUsageChargeService, cache: :memory do
  subject(:full_usage_charge_service) do
    described_class.new(
      invoice:,
      subscription:,
      charge:,
      boundaries:,
      date_service:,
      applied_filters: {nil => nil},
      options:,
      cache:,
      max_timestamp:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: "monthly") }
  let(:current_date) { DateTime.parse("2025-06-15") }
  let(:timestamp) { current_date }
  let(:subscription_started_at) { DateTime.parse("2025-01-01") }
  let(:subscription) { create(:subscription, plan:, customer:, started_at: subscription_started_at) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"}) }
  let(:date_service) { Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true) }
  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: subscription.started_at,
      to_datetime: date_service.to_datetime,
      charges_from_datetime: subscription.started_at,
      charges_to_datetime: date_service.charges_to_datetime,
      issuing_date: date_service.next_end_of_period,
      charges_duration: date_service.charges_duration_in_days,
      timestamp:
    )
  end
  let(:options) do
    Fees::ChargeService::Options.new(
      context: :current_usage,
      usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true),
      skip_adjusted_fees: true
    )
  end
  let(:invoice) do
    Invoice.new(
      organization:,
      billing_entity: customer.billing_entity,
      customer:,
      issuing_date: boundaries.issuing_date,
      currency: plan.amount_currency
    )
  end
  let(:cache) { true }
  let(:max_timestamp) { nil }

  def create_value_event(value:, event_timestamp:)
    create(:event, organization:, subscription:, customer:, code: billable_metric.code,
      timestamp: event_timestamp, properties: {value:})
  end

  def single_window_fees
    described_class.call!(
      invoice:, subscription:, charge:, boundaries:, date_service:, applied_filters: {nil => nil}, options:, cache: false
    ).fees
  end

  before { organization.enable_feature_flag!(:lazy_charge_usage_cache) }

  describe "#call" do
    context "when the subscription started before the current billing period" do
      before do
        create_value_event(value: 4, event_timestamp: DateTime.parse("2025-02-10"))
        create_value_event(value: 6, event_timestamp: DateTime.parse("2025-03-20"))
        create_value_event(value: 3, event_timestamp: DateTime.parse("2025-06-05"))
        create_value_event(value: 7, event_timestamp: DateTime.parse("2025-06-20"))
      end

      it "returns the same total units and amount as a single-window computation" do
        travel_to(current_date) do
          split_fee = full_usage_charge_service.call!.fees.sole
          reference_fee = single_window_fees.sole

          expect(split_fee.units).to eq(reference_fee.units)
          expect(split_fee.amount_cents).to eq(reference_fee.amount_cents)
        end
      end

      it "caches the prior periods window and the current period window separately" do
        prior_periods_key = Subscriptions::ChargeCacheService.new(subscription:, charge:, prior_periods: true).cache_key
        ordinary_key = Subscriptions::ChargeCacheService.new(subscription:, charge:).cache_key
        full_usage_key = Subscriptions::ChargeCacheService.new(subscription:, charge:, full_usage: true).cache_key

        travel_to(current_date) do
          full_usage_charge_service.call!

          expect(Rails.cache.exist?(prior_periods_key)).to be(true)
          expect(Rails.cache.exist?(ordinary_key)).to be(true)
          expect(Rails.cache.exist?(full_usage_key)).to be(false)
        end
      end
    end

    context "with an event on either side of the period boundary" do
      let(:boundary_timestamp) { date_service.charges_from_datetime }

      before do
        create_value_event(value: 2, event_timestamp: boundary_timestamp)
        create_value_event(value: 5, event_timestamp: boundary_timestamp - Fees::FullUsageChargeService::PERIOD_BOUNDARY_GAP)
      end

      it "counts each boundary event exactly once" do
        travel_to(current_date) do
          split_fee = full_usage_charge_service.call!.fees.sole
          reference_fee = single_window_fees.sole

          expect(split_fee.units).to eq(reference_fee.units)
          expect(split_fee.amount_cents).to eq(reference_fee.amount_cents)
        end
      end
    end

    describe "gates that keep the split path from being taken" do
      before do
        allow(Fees::MergePeriodFeesService).to receive(:call!).and_call_original
        create_value_event(value: 3, event_timestamp: DateTime.parse("2025-06-05"))
      end

      it "takes the split path when every gate is open" do
        travel_to(current_date) { full_usage_charge_service.call! }

        expect(Fees::MergePeriodFeesService).to have_received(:call!)
      end

      context "when the cache is disabled" do
        let(:cache) { false }

        it "does not take the split path" do
          travel_to(current_date) { full_usage_charge_service.call! }

          expect(Fees::MergePeriodFeesService).not_to have_received(:call!)
        end
      end

      context "when a projected usage is requested" do
        let(:options) do
          Fees::ChargeService::Options.new(
            context: :current_usage,
            usage_filters: UsageFilters.new(filter_by_charge_id: charge.id, full_usage: true),
            calculate_projected_usage: true,
            skip_adjusted_fees: true
          )
        end

        it "does not take the split path" do
          travel_to(current_date) { full_usage_charge_service.call! }

          expect(Fees::MergePeriodFeesService).not_to have_received(:call!)
        end
      end

      context "when a max_timestamp is given" do
        let(:max_timestamp) { date_service.charges_to_datetime }

        it "does not take the split path" do
          travel_to(current_date) { full_usage_charge_service.call! }

          expect(Fees::MergePeriodFeesService).not_to have_received(:call!)
        end
      end

      context "when the subscription started within the current period" do
        let(:subscription_started_at) { DateTime.parse("2025-06-10") }

        it "does not take the split path" do
          travel_to(current_date) { full_usage_charge_service.call! }

          expect(Fees::MergePeriodFeesService).not_to have_received(:call!)
        end
      end

      context "when the metric is recurring" do
        let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "value") }

        it "does not take the split path" do
          travel_to(current_date) { full_usage_charge_service.call! }

          expect(Fees::MergePeriodFeesService).not_to have_received(:call!)
        end
      end
    end

    describe "the recurring lifetime shortcut" do
      let(:ordinary_key) { Subscriptions::ChargeCacheService.new(subscription:, charge:).cache_key }
      let(:full_usage_key) { Subscriptions::ChargeCacheService.new(subscription:, charge:, full_usage: true).cache_key }

      before { create_value_event(value: 5, event_timestamp: DateTime.parse("2025-06-05")) }

      context "with a sum_agg metric" do
        let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "value") }

        it "caches under the ordinary key, not the full-usage key" do
          travel_to(current_date) do
            full_usage_charge_service.call!

            expect(Rails.cache.exist?(ordinary_key)).to be(true)
            expect(Rails.cache.exist?(full_usage_key)).to be(false)
          end
        end
      end

      context "with a unique_count_agg metric" do
        let(:billable_metric) { create(:unique_count_billable_metric, :recurring, organization:, field_name: "value") }

        it "caches under the ordinary key, not the full-usage key" do
          travel_to(current_date) do
            full_usage_charge_service.call!

            expect(Rails.cache.exist?(ordinary_key)).to be(true)
            expect(Rails.cache.exist?(full_usage_key)).to be(false)
          end
        end
      end
    end

    describe "recurring charges excluded from the lifetime shortcut" do
      let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "value") }
      let(:ordinary_key) { Subscriptions::ChargeCacheService.new(subscription:, charge:).cache_key }
      let(:full_usage_key) { Subscriptions::ChargeCacheService.new(subscription:, charge:, full_usage: true).cache_key }

      before { create_value_event(value: 5, event_timestamp: DateTime.parse("2025-06-05")) }

      context "when the charge is pay in advance" do
        let(:charge) { create(:standard_charge, plan:, billable_metric:, pay_in_advance: true, properties: {amount: "10"}) }

        it "caches under the full-usage key instead of the shortcut" do
          travel_to(current_date) do
            full_usage_charge_service.call!

            expect(Rails.cache.exist?(full_usage_key)).to be(true)
            expect(Rails.cache.exist?(ordinary_key)).to be(false)
          end
        end
      end

      context "when the charge is prorated" do
        let(:charge) { create(:standard_charge, plan:, billable_metric:, prorated: true, properties: {amount: "10"}) }

        it "caches under the full-usage key instead of the shortcut" do
          travel_to(current_date) do
            full_usage_charge_service.call!

            expect(Rails.cache.exist?(full_usage_key)).to be(true)
            expect(Rails.cache.exist?(ordinary_key)).to be(false)
          end
        end
      end
    end
  end
end
