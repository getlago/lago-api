# frozen_string_literal: true

require "rails_helper"

# Every path that moves a subscription's billing dates has to leave it with a period covering now,
# and the next one, because a consumer keys usage off these rows. This drives those paths through the
# API so a new one that forgets to maintain them shows up here.
describe "Subscription Billing Periods Scenarios" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:plan) { create(:plan, organization:, interval: :monthly, amount_cents: 1000) }

  def current_period_for(subscription)
    SubscriptionBillingPeriod.covering(Time.current).where(scope_id: subscription.id)
      .pick(:period_from, :period_to)
  end

  def expect_period(actual, expected)
    expect(actual.first).to match_datetime(expected.first)
    expect(actual.last).to match_datetime(expected.last)
  end

  def periods_for(subscription)
    SubscriptionBillingPeriod.where(scope_id: subscription.id).order(:period_from)
      .pluck(:period_from, :period_to)
  end

  def subscribe(plan_code: plan.code, external_id: customer.external_id)
    create_subscription(
      {
        external_customer_id: customer.external_id,
        external_id:,
        plan_code:
      }
    )
    customer.subscriptions.order(:created_at).last
  end

  it "materializes periods when a subscription is created" do
    travel_to(Time.utc(2024, 3, 10)) do
      subscription = subscribe

      expect(periods_for(subscription).size).to eq(2)
      expect(SubscriptionBillingPeriod.covering(Time.current).where(scope_id: subscription.id)).to be_present
    end
  end

  it "leaves the next period in place so a rollover finds a covering row" do
    travel_to(Time.utc(2024, 3, 10)) do
      subscription = subscribe
      current, following = periods_for(subscription)

      expect(following.first).to match_datetime(current.last + 1.second)
    end
  end

  it "clamps the period when a subscription is terminated" do
    subscription = nil

    travel_to(Time.utc(2024, 3, 10)) { subscription = subscribe }

    travel_to(Time.utc(2024, 3, 20)) do
      terminate_subscription(subscription)

      periods = periods_for(subscription)
      expect(periods.size).to eq(1)
      expect(periods.first.last).to match_datetime(subscription.reload.terminated_at)
    end
  end

  it "materializes periods for both subscriptions of an upgrade" do
    subscription = nil
    higher_plan = nil

    travel_to(Time.utc(2024, 3, 10)) do
      subscription = subscribe
      higher_plan = create(:plan, organization:, interval: :monthly, amount_cents: 5000)
    end

    travel_to(Time.utc(2024, 3, 20)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: subscription.external_id,
          plan_code: higher_plan.code
        }
      )

      upgraded = customer.subscriptions.order(:created_at).last
      expect(upgraded.id).not_to eq(subscription.id)

      # The terminated one keeps a period covering the usage it is billed for, the new one opens its
      # own.
      expect(periods_for(subscription)).not_to be_empty
      expect(periods_for(upgraded)).not_to be_empty
    end
  end

  # While the applicable timezone differs from the one of the last invoice, DatesService snaps the
  # charges boundaries to that invoice so that the periods neither overlap nor leave a hole. The
  # snap is bounded to the period adjacent to that invoice, and the invoice closing that period is
  # computed with the same rule, so the stored period and the invoice it is billed by agree.
  it "keeps the periods aligned with the invoices across a timezone change", :premium, transaction: false do
    subscription = nil

    travel_to(Time.utc(2024, 3, 10)) { subscription = subscribe }

    # First invoice, issued in UTC.
    travel_to(Time.utc(2024, 4, 1, 1)) { perform_billing }

    travel_to(Time.utc(2024, 4, 5)) do
      clock_job do
        create_or_update_customer({external_id: customer.external_id, timezone: "America/New_York"})
      end
    end

    # Second invoice, issued in the new timezone: it closes the snapped period.
    travel_to(Time.utc(2024, 5, 1, 5)) do
      perform_billing

      expect(subscription.invoice_subscriptions.count).to eq(2)

      invoiced = subscription.invoice_subscriptions.order(:charges_to_datetime).last
      billed_period = periods_for(subscription).find { |from, _| from == invoiced.charges_from_datetime }

      expect(billed_period).not_to be_nil
      expect(billed_period.last).to match_datetime(invoiced.charges_to_datetime)

      dates = Subscriptions::DatesService.new_instance(subscription.reload, Time.current, current_usage: true)
      expect_period(current_period_for(subscription), [dates.charges_from_datetime, dates.charges_to_datetime])
    end
  end

  # Timezone is a premium attribute, so the assignment is license-gated.
  it "re-derives periods when the customer timezone changes", :premium, transaction: false do
    travel_to(Time.utc(2024, 3, 10)) do
      subscription = subscribe

      # period_from is clamped to the subscription start, so the timezone shows up on period_to: the
      # end of March in UTC, then the end of March in New York.
      expect(periods_for(subscription).first.last).to match_datetime(Time.utc(2024, 3, 31).end_of_day)

      clock_job do
        create_or_update_customer({external_id: customer.external_id, timezone: "America/New_York"})
      end

      expect(periods_for(subscription).first.last).to match_datetime(Time.utc(2024, 4, 1, 3, 59, 59))
    end
  end
end
