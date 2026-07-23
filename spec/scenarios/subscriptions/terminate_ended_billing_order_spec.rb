# frozen_string_literal: true

require "rails_helper"

# Path A behaviour: the periodic biller is NOT prevented from billing on the
# ending day. Completed periods are billed by the periodic biller (as usual),
# and the termination flow bills only the final partial period. A period-based
# dedup guard ensures a period billed by termination cannot also be billed
# periodically (and vice versa).
#
# Clock order within an hour (see clock.rb):
#   *:05  Clock::TerminateEndedSubscriptionsJob   (terminate ended subscriptions)
#   *:10  Clock::SubscriptionsBillerJob           (bill customers)
describe "Subscription termination vs billing order" do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: "") }
  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:) }

  # Monthly, billed in arrears. Subscription fee = 100.00.
  let(:plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      amount_cents: 10_000,
      pay_in_advance: false
    )
  end

  # Metered usage: sum of the `amount` property. Standard charge at 1.00 / unit,
  # billed in arrears, so N units => N units of charge fees => N * 100 cents.
  let(:billable_metric) do
    create(
      :billable_metric,
      organization:,
      name: "Usage",
      code: "usage",
      aggregation_type: "sum_agg",
      field_name: "amount",
      recurring: false
    )
  end

  before do
    create(
      :standard_charge,
      billable_metric:,
      plan:,
      invoiceable: true,
      pay_in_advance: false,
      properties: {amount: "1"}
    )
  end

  # --- helpers -------------------------------------------------------------

  def create_test_subscription(started_at:, ending_at:, billing_time:)
    travel_to(started_at) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time:,
          subscription_at: started_at.iso8601,
          ending_at: ending_at.iso8601
        }
      )
    end
    customer.subscriptions.first
  end

  def ingest_usage(amount)
    create_event(
      {
        code: billable_metric.code,
        transaction_id: SecureRandom.uuid,
        external_subscription_id: customer.external_id,
        properties: {amount: amount.to_s}
      }
    )
  end

  # Real Clock order: terminate (*:05) before bill (*:10).
  def run_clock_terminate_then_bill
    Clock::TerminateEndedSubscriptionsJob.perform_now
    perform_all_enqueued_jobs
    Clock::SubscriptionsBillerJob.perform_now
    perform_all_enqueued_jobs
  end

  # Reverse order: the biller runs while the termination enqueued at *:05 has not
  # been processed yet (queue lag). This is the double-billing window.
  def run_clock_bill_then_terminate
    Clock::SubscriptionsBillerJob.perform_now
    perform_all_enqueued_jobs
    Clock::TerminateEndedSubscriptionsJob.perform_now
    perform_all_enqueued_jobs
  end

  def charge_units_total(subscription)
    subscription.reload.invoices.sum { |inv| inv.fees.where(fee_type: :charge).sum(:units) }.to_i
  end

  def subscription_fees_cents(subscription)
    subscription.reload.invoices.sum { |inv| inv.fees.where(fee_type: :subscription).sum(:amount_cents) }
  end

  # Count of invoice_subscriptions covering the exact same [from, to] period,
  # used to prove a period is billed at most once.
  def invoice_subscriptions_for(subscription, from:, to:)
    subscription.invoice_subscriptions.where(
      from_datetime: from.beginning_of_day.utc..to.end_of_day.utc
    )
  end

  # --- 1. Mid-day ending on the billing day (usage accounting) -------------
  #
  # start 22 Jun 15:33, end 22 Jul 15:33 (anniversary). 22 Jul is both the
  # billing day and the ending day. Under Path A the biller invoices the
  # completed period 1 at 00:xx (sub still active), and termination later bills
  # the partial period 2. No usage is dropped.
  context "when an anniversary subscription ends mid-day on its billing day" do
    let(:started_at) { Time.zone.parse("2025-06-22T15:33:00") }
    let(:ending_at) { Time.zone.parse("2025-07-22T15:33:00") }

    it "bills the completed period periodically and the partial period on termination" do
      subscription = create_test_subscription(started_at:, ending_at:, billing_time: "anniversary")

      # (A) period 1
      travel_to(Time.zone.parse("2025-07-05T12:00:00")) { ingest_usage(10) }

      # Anniversary day tick: sub still active (ends 15:33), biller bills period 1.
      travel_to(Time.zone.parse("2025-07-22T00:05:00")) do
        run_clock_terminate_then_bill
        expect(subscription.reload).to be_active
        expect(subscription.invoices.count).to eq(1)
      end

      # (B) period 2, before ending
      travel_to(Time.zone.parse("2025-07-22T10:00:00")) { ingest_usage(20) }
      # (C) 1 min after ending_at — accepted (sub still active) but NOT billed, because
      # terminated_at is pinned to ending_at (15:33).
      travel_to(Time.zone.parse("2025-07-22T16:34:00")) { ingest_usage(40) }

      # Tick after ending: termination fires and bills the partial period 2, up to
      # terminated_at = ending_at (15:33).
      travel_to(Time.zone.parse("2025-07-22T17:05:00")) do
        run_clock_terminate_then_bill
      end

      subscription.reload
      expect(subscription).to be_terminated
      expect(subscription.invoices.count).to eq(2)

      # No usage lost, none double-counted. Usage up to ending_at is billed (A in period 1,
      # B in period 2); the post-ending event C is excluded: A + B = 10 + 20 = 30.
      expect(charge_units_total(subscription)).to eq(30)

      # Period 1 full month + period 2 prorate (up to ending_at).
      expect(subscription_fees_cents(subscription)).to be > 10_000
    end
  end

  # --- 2. Ending exactly at the period boundary (known-good contrast) -------
  context "when an anniversary subscription ends exactly at the period boundary" do
    let(:started_at) { Time.zone.parse("2025-06-22T00:00:00") }
    let(:ending_at) { Time.zone.parse("2025-07-22T00:00:00") }

    it "bills the full period once, with all its usage" do
      subscription = create_test_subscription(started_at:, ending_at:, billing_time: "anniversary")

      travel_to(Time.zone.parse("2025-07-05T12:00:00")) { ingest_usage(10) }
      travel_to(Time.zone.parse("2025-07-21T12:00:00")) { ingest_usage(20) }

      # Termination fires at 00:05 (before the biller in the same tick) and bills
      # the completed period; the biller then skips the now-terminated sub.
      travel_to(Time.zone.parse("2025-07-22T00:05:00")) do
        run_clock_terminate_then_bill
      end

      subscription.reload
      expect(subscription).to be_terminated
      expect(charge_units_total(subscription)).to eq(30)          # 10 + 20, all period 1
      expect(subscription_fees_cents(subscription)).to eq(10_000) # full month, once

      # The completed period is billed exactly once.
      expect(
        invoice_subscriptions_for(subscription, from: started_at, to: ending_at - 1.day).count
      ).to eq(1)
    end
  end

  # --- 3. Near-midnight calendar ending, realistic clock order --------------
  #
  # Calendar monthly bills on the 1st. Sub ends 31 Jul 23:59, so termination
  # slips to the next tick (1 Aug 00:05), which is the billing day. Terminate
  # runs first and bills July; the biller then skips the terminated sub.
  context "when a calendar subscription ends just before midnight of the billing day" do
    let(:started_at) { Time.zone.parse("2025-07-01T00:00:00") }
    let(:ending_at) { Time.zone.parse("2025-07-31T23:59:00") }

    it "bills July exactly once (terminate before bill)" do
      subscription = create_test_subscription(started_at:, ending_at:, billing_time: "calendar")

      travel_to(Time.zone.parse("2025-07-10T12:00:00")) { ingest_usage(15) }

      travel_to(Time.zone.parse("2025-08-01T00:05:00")) do
        run_clock_terminate_then_bill
      end

      subscription.reload
      expect(subscription).to be_terminated
      expect(charge_units_total(subscription)).to eq(15)          # billed once, not doubled
      expect(
        invoice_subscriptions_for(subscription, from: started_at, to: Time.zone.parse("2025-07-31")).count
      ).to eq(1)                                                  # July billed exactly once
    end

    # Reverse order: the biller bills July while the sub is still active (the
    # termination job hasn't processed yet). Termination must NOT re-bill July.
    it "does not double-bill July when billing runs before termination" do
      subscription = create_test_subscription(started_at:, ending_at:, billing_time: "calendar")

      travel_to(Time.zone.parse("2025-07-10T12:00:00")) { ingest_usage(15) }

      travel_to(Time.zone.parse("2025-08-01T00:10:00")) do
        run_clock_bill_then_terminate
      end

      subscription.reload
      expect(subscription).to be_terminated
      expect(charge_units_total(subscription)).to eq(15)           # billed once, not doubled
      expect(subscription_fees_cents(subscription)).to eq(10_000)  # July once, no next-period sliver
      expect(
        invoice_subscriptions_for(subscription, from: started_at, to: Time.zone.parse("2025-07-31")).count
      ).to eq(1)                                                   # July billed exactly once
    end
  end
end
