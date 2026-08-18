# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::UpsertService do
  subject(:result) { described_class.call(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:timezone) { "UTC" }
  let(:plan) { create(:plan, organization:, interval:, pay_in_advance:) }
  let(:interval) { :monthly }
  let(:pay_in_advance) { false }
  let(:billing_time) { :calendar }
  let(:subscription_at) { Time.utc(2024, 1, 15) }
  let(:timestamp) { Time.utc(2024, 3, 10) }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      customer:,
      plan:,
      billing_time:,
      subscription_at:,
      started_at: subscription_at,
      status: :active
    )
  end

  def persisted_periods
    SubscriptionBillingPeriod.where(scope_id: subscription.id).order(:period_from)
      .pluck(:period_from, :period_to)
  end

  def boundaries_at(time)
    dates = Subscriptions::DatesService.new_instance(subscription, time, current_usage: true)
    [dates.charges_from_datetime, dates.charges_to_datetime]
  end

  # Postgres keeps microseconds where DatesService returns nanoseconds, so an end-of-day boundary
  # never compares equal; match_datetime compares to the second.
  def expect_period(actual, expected)
    expect(actual.first).to match_datetime(expected.first)
    expect(actual.last).to match_datetime(expected.last)
  end

  def expect_contiguous(current, following)
    expect(following.first).to match_datetime(current.last + 1.second)
  end

  it "stores the current period and the next one" do
    expect { result }.to change(SubscriptionBillingPeriod, :count).by(2)

    current, following = persisted_periods
    expect_period(current, boundaries_at(timestamp))
    expect_contiguous(current, following)
  end

  it "stores the charges boundaries, the customer and the scope" do
    result

    period = SubscriptionBillingPeriod.order(:period_from).first
    expect(period.period_from).to match_datetime(boundaries_at(timestamp).first)
    expect(period.customer_id).to eq(customer.id)
    expect(period.organization_id).to eq(organization.id)
    expect(period.scope_type).to eq("Subscription")
    expect(period.scope_id).to eq(subscription.id)
  end

  it "returns the periods it wrote" do
    expect(result.periods.map(&:period_from)).to eq(persisted_periods.map(&:first))
  end

  Plan::INTERVALS.each do |plan_interval|
    context "with a #{plan_interval} plan" do
      let(:interval) { plan_interval }

      %i[calendar anniversary].each do |plan_billing_time|
        context "when billing_time is #{plan_billing_time}" do
          let(:billing_time) { plan_billing_time }

          it "stores two contiguous periods matching DatesService" do
            result

            current, following = persisted_periods
            expect_period(current, boundaries_at(timestamp))
            expect_contiguous(current, following)
          end
        end
      end
    end
  end

  context "when the plan bills its charges monthly" do
    let(:interval) { :yearly }
    let(:plan) { create(:plan, organization:, interval: :yearly, bill_charges_monthly: true) }

    # The charges period is monthly even though the plan is yearly, and it is the charges period
    # that has to be stored.
    it "stores the monthly charges period, not the yearly plan period" do
      result

      current = persisted_periods.first
      expect_period(current, boundaries_at(timestamp))
      expect(current.first).to match_datetime(Time.utc(2024, 3, 1))
    end
  end

  context "when the plan is pay in advance" do
    let(:pay_in_advance) { true }

    it "stores two contiguous periods" do
      result

      current, following = persisted_periods
      expect_period(current, boundaries_at(timestamp))
      expect_contiguous(current, following)
    end
  end

  context "with a non-UTC customer timezone" do
    # +05:45, so a local day boundary is not a whole hour in UTC.
    let(:timezone) { "Asia/Kathmandu" }

    it "stores the boundaries in the customer timezone" do
      result

      current, following = persisted_periods
      expect_period(current, boundaries_at(timestamp))
      expect_contiguous(current, following)
    end
  end

  context "when the subscription is terminated" do
    let(:subscription) do
      create(
        :subscription,
        organization:, customer:, plan:, billing_time:, subscription_at:,
        started_at: subscription_at,
        status: :terminated,
        terminated_at: Time.utc(2024, 3, 5)
      )
    end

    it "stores only the period that is being closed" do
      expect { result }.to change(SubscriptionBillingPeriod, :count).by(1)

      expect(persisted_periods.first.last).to match_datetime(subscription.terminated_at)
    end
  end

  # A downgrade takes effect on the billing day, so the previous subscription is terminated at the
  # very instant the next period opens: DatesService clamps charges_to to terminated_at and the
  # boundaries collapse onto each other.
  context "when the subscription is terminated at the instant a period opens" do
    let(:billing_time) { :calendar }
    let(:subscription) do
      create(
        :subscription,
        organization:, customer:, plan:, billing_time:, subscription_at:,
        started_at: subscription_at,
        status: :terminated,
        terminated_at: Time.utc(2024, 3, 1)
      )
    end

    it "stores no period rather than one that does not move forward" do
      expect { result }.not_to change(SubscriptionBillingPeriod, :count)
      expect(result.periods).to be_empty
    end

    it "still discards the periods that can no longer happen" do
      stale = create(
        :subscription_billing_period,
        subscription:,
        period_from: Time.utc(2024, 3, 1),
        period_to: Time.utc(2024, 3, 31).end_of_day
      )
      closed = create(
        :subscription_billing_period,
        subscription:,
        period_from: Time.utc(2024, 2, 1),
        period_to: Time.utc(2024, 2, 29).end_of_day
      )

      result

      expect(SubscriptionBillingPeriod.where(id: stale.id)).to be_empty
      expect(SubscriptionBillingPeriod.where(id: closed.id)).to be_present
    end
  end

  context "when the subscription was terminated beyond the grace period" do
    let(:subscription) do
      create(
        :subscription,
        organization:, customer:, plan:, billing_time:, subscription_at:,
        started_at: subscription_at,
        status: :terminated,
        terminated_at: timestamp - described_class::TERMINATED_GRACE_PERIOD - 1.day
      )
    end

    it "does nothing" do
      expect { result }.not_to change(SubscriptionBillingPeriod, :count)
      expect(result.periods).to be_empty
    end
  end

  context "when the feature flag is disabled" do
    let(:organization) { create(:organization, feature_flags: []) }

    it "does nothing" do
      expect { result }.not_to change(SubscriptionBillingPeriod, :count)
      expect(result.periods).to be_empty
    end
  end

  context "when the subscription is pending" do
    let(:subscription) { create(:subscription, :pending, organization:, customer:, plan:, billing_time:) }

    it "does nothing" do
      expect { result }.not_to change(SubscriptionBillingPeriod, :count)
    end
  end

  context "when the subscription has no started_at" do
    let(:subscription) do
      create(:subscription, organization:, customer:, plan:, billing_time:, subscription_at:, started_at: nil, status: :active)
    end

    it "does nothing" do
      expect { result }.not_to change(SubscriptionBillingPeriod, :count)
    end
  end

  describe "convergence" do
    it "keeps periods that have already closed" do
      past = create(
        :subscription_billing_period,
        subscription:,
        period_from: Time.utc(2020, 1, 1),
        period_to: Time.utc(2020, 1, 31).end_of_day
      )

      result

      expect(SubscriptionBillingPeriod.where(id: past.id)).to be_present
      expect(persisted_periods.size).to eq(3)
    end

    it "keeps the period it rolled out of" do
      described_class.call(subscription:, timestamp: Time.utc(2024, 2, 10))

      expect { described_class.call(subscription:, timestamp:) }
        .to change(SubscriptionBillingPeriod, :count).by(1)

      # February, March and April, rather than March and April alone.
      expect(persisted_periods.size).to eq(3)
      expect(persisted_periods.first.first).to match_datetime(Time.utc(2024, 2, 1))
    end

    # A moved boundary is the same period shifted, so the row it replaces overlaps it and cannot
    # stay. The overlap constraint is deferred to commit for exactly this.
    it "replaces a period whose boundary moved, despite the overlap" do
      current_from, current_to = boundaries_at(timestamp)
      shifted = create(
        :subscription_billing_period,
        subscription:,
        period_from: current_from - 1.day,
        period_to: current_to - 1.day
      )

      expect { result }.not_to raise_error

      expect(SubscriptionBillingPeriod.where(id: shifted.id)).to be_empty
      expect_period(persisted_periods.first, [current_from, current_to])
    end
  end

  describe "locking" do
    # The overlap constraint is deferred, so a concurrent writer is only caught at COMMIT, and by
    # then it is the enclosing lifecycle transaction that fails. The lock therefore has to be held
    # to commit rather than released at the end of the block.
    it "holds the advisory lock until the transaction commits" do
      allow(SubscriptionBillingPeriod).to receive(:with_advisory_lock!).and_call_original

      result

      expect(SubscriptionBillingPeriod).to have_received(:with_advisory_lock!).with(
        "subscription_billing_periods_#{subscription.id}",
        transaction: true,
        timeout_seconds: described_class::LOCK_TIMEOUT
      )
    end

    it "raises rather than writing when the lock cannot be acquired" do
      allow(SubscriptionBillingPeriod).to receive(:with_advisory_lock!)
        .and_raise(WithAdvisoryLock::FailedToAcquireLock, "subscription_billing_periods")

      expect { result }.to raise_error(WithAdvisoryLock::FailedToAcquireLock)
        .and not_change(SubscriptionBillingPeriod, :count)
    end
  end

  describe "idempotency" do
    it "writes the same rows and preserves created_at" do
      described_class.call(subscription:, timestamp:)
      before_ids = SubscriptionBillingPeriod.order(:period_from).pluck(:id, :created_at)

      expect { described_class.call(subscription:, timestamp:) }
        .not_to change(SubscriptionBillingPeriod, :count)

      expect(SubscriptionBillingPeriod.order(:period_from).pluck(:id, :created_at)).to eq(before_ids)
    end
  end
end
