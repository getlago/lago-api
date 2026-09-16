# frozen_string_literal: true

require "rails_helper"

describe "Repeating fixed charge units emits no event", :premium do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:add_on) { create(:add_on, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0, interval: "monthly", pay_in_advance: true) }

  let(:fixed_charge) do
    create(
      :fixed_charge,
      plan:,
      add_on:,
      units: 0,
      properties: {amount: "10"},
      prorated: false,
      pay_in_advance: true
    )
  end

  let(:subscription_date) { DateTime.new(2024, 3, 1) }
  let(:subscription) { customer.subscriptions.sole }

  # Immediate changes are stamped now; deferred ones are stamped at the start of the next
  # period. The two lanes therefore carry separate baselines, and a repeat is judged against
  # whichever event is already effective at the timestamp the new one would take.
  # A method, not a `let`: a memoized relation caches its records after the first load and
  # would report the same units for every step below.
  def event_units
    FixedChargeEvent.where(subscription:, fixed_charge:).order(:created_at).map { |e| e.units.to_i }
  end

  def update_units(units, apply_now:, at:)
    travel_to(at) do
      update_subscription_fixed_charge(
        subscription,
        fixed_charge.code,
        {units:, apply_units_immediately: apply_now}
      )
    end
  end

  before do
    fixed_charge

    travel_to subscription_date do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: "sub_#{customer.external_id}",
          plan_code: plan.code,
          billing_time: "calendar",
          plan_overrides: {fixed_charges: [{id: fixed_charge.id, units: 10}]}
        }
      )
    end
  end

  it "emits an event only when the units differ from the ones already effective at its timestamp" do
    expect(event_units).to eq([10])

    # 15 differs from the effective 10, and lands at the start of the next period.
    update_units(15, apply_now: false, at: subscription_date + 1.hour)
    expect(event_units).to eq([10, 15])

    # 10 now: the immediate lane is still on 10, so there is nothing to record.
    update_units(10, apply_now: true, at: subscription_date + 2.hours)
    expect(event_units).to eq([10, 15])

    # 15 later: the deferred lane already holds 15.
    update_units(15, apply_now: false, at: subscription_date + 3.hours)
    expect(event_units).to eq([10, 15])

    # 10 now again, still a repeat of the immediate lane.
    update_units(10, apply_now: true, at: subscription_date + 4.hours)
    expect(event_units).to eq([10, 15])

    # 10 later: this one supersedes the pending 15, so it must be recorded even though 10
    # is what the subscription bills today.
    update_units(10, apply_now: false, at: subscription_date + 5.hours)
    expect(event_units).to eq([10, 15, 10])
  end

  it "bills only the change that was applied immediately" do
    update_units(15, apply_now: false, at: subscription_date + 1.hour)
    update_units(10, apply_now: true, at: subscription_date + 2.hours)
    update_units(15, apply_now: false, at: subscription_date + 3.hours)

    travel_to subscription_date + 4.hours do
      perform_all_enqueued_jobs
    end

    # Only the subscription's own pay in advance invoice: the repeats never scheduled a
    # billing run, and the deferred change is not due until the next period.
    expect(subscription.invoices.count).to eq(1)
  end
end
