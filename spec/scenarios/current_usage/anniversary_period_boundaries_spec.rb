# frozen_string_literal: true

require "rails_helper"

# Anniversary subscriptions whose day has to be clamped to a shorter month used to return charges
# periods that overlapped, left a gap, or slid depending on when they were asked for. See
# Subscriptions::DatesService for the fencepost model these periods follow.
describe "Anniversary current usage period boundaries Scenarios" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

  def subscribe_on(date, interval:)
    travel_to(date) do
      plan = create(:plan, organization:, interval:, amount_cents: 0, pay_in_advance: false)
      create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"})

      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: "anniversary"
        },
        as: :model
      )
    end
  end

  def usage_on(date, subscription:)
    travel_to(date) do
      fetch_current_usage(customer:, subscription:)
      json[:customer_usage]
    end
  end

  def period_on(date, subscription:)
    usage = usage_on(date, subscription:)
    [Time.iso8601(usage[:from_datetime]), Time.iso8601(usage[:to_datetime])]
  end

  context "with a yearly subscription starting on a leap day" do
    let(:subscription) { subscribe_on(DateTime.new(2024, 2, 29), interval: :yearly) }

    # The anniversary clamps to 28 Feb in a common year, so the 27th closes the first period and the
    # 28th opens the second. Both ends used to land on the 28th.
    it "hands the clamped anniversary day to a single period" do
      expect(period_on(DateTime.new(2025, 2, 20), subscription:))
        .to eq([Time.utc(2024, 2, 29), Time.utc(2025, 2, 27, 23, 59, 59)])

      expect(period_on(DateTime.new(2025, 3, 10), subscription:))
        .to eq([Time.utc(2025, 2, 28), Time.utc(2026, 2, 27, 23, 59, 59)])
    end

    it "counts an event on the clamped anniversary day once" do
      # Resolved before travelling: creating the subscription travels itself, and travel_to refuses
      # to nest.
      external_subscription_id = subscription.external_id

      travel_to(DateTime.new(2025, 2, 28, 12)) do
        create_event({code: billable_metric.code, external_subscription_id:})
      end

      opening_period = usage_on(DateTime.new(2025, 3, 10), subscription:)
      closing_period = usage_on(DateTime.new(2025, 2, 20), subscription:)

      expect(opening_period[:charges_usage].sum { |charge| charge[:events_count] }).to eq(1)
      expect(closing_period[:charges_usage].sum { |charge| charge[:events_count] }).to eq(0)
    end
  end

  context "with a quarterly subscription starting on a month end" do
    let(:subscription) { subscribe_on(DateTime.new(2022, 1, 31), interval: :quarterly) }

    # A month-end day used to be treated as an anniversary even in a month that is not a billing
    # month, which moved the period forward one month at a time instead of one quarter.
    it "holds the quarter instead of sliding monthly" do
      expect(period_on(DateTime.new(2022, 5, 31), subscription:).first).to eq(Time.utc(2022, 4, 30))
    end

    # July's anniversary is the 31st, so the 30th still belongs to the April period.
    it "keeps the day before an anniversary in the previous period" do
      expect(period_on(DateTime.new(2022, 7, 30), subscription:).first).to eq(Time.utc(2022, 4, 30))
    end

    # The anniversary is re-derived from the subscription every period, so April being short does
    # not drag the following periods onto the 30th.
    it "does not let a clamped month drag the following periods" do
      expect(period_on(DateTime.new(2022, 8, 15), subscription:).first).to eq(Time.utc(2022, 7, 31))
    end

    it "returns periods that meet without overlapping" do
      closing = period_on(DateTime.new(2022, 4, 15), subscription:)
      opening = period_on(DateTime.new(2022, 5, 15), subscription:)

      expect(closing.last).to eq(Time.utc(2022, 4, 29, 23, 59, 59))
      expect(opening.first).to eq(Time.utc(2022, 4, 30))
    end
  end

  context "with a quarterly subscription starting on the 29th of a 31-day month" do
    let(:subscription) { subscribe_on(DateTime.new(2022, 1, 29), interval: :quarterly) }

    # February is shorter than the subscription day, and its length used to leak into the resolved
    # anniversary of a different billing month, returning 28 Jan.
    it "resolves the anniversary from the subscription day" do
      expect(period_on(DateTime.new(2022, 2, 28), subscription:).first).to eq(Time.utc(2022, 1, 29))
    end
  end

  context "with a semiannual subscription starting on a month end" do
    let(:subscription) { subscribe_on(DateTime.new(2021, 1, 31), interval: :semiannual) }

    # April is not a billing month for a January-anchored semiannual subscription, so 30 Apr belongs
    # to the period opened in January rather than starting one of its own.
    it "ignores month ends outside a billing month" do
      expect(period_on(DateTime.new(2021, 4, 30), subscription:).first).to eq(Time.utc(2021, 1, 31))
    end
  end

  context "with a quarterly subscription starting on the end of a 30-day month" do
    let(:subscription) { subscribe_on(DateTime.new(2021, 4, 30), interval: :quarterly) }

    # May is not a billing month, but its own month end used to be taken for an anniversary, which
    # moved the period start to 30 May.
    it "ignores month ends outside a billing month" do
      expect(period_on(DateTime.new(2021, 5, 31), subscription:).first).to eq(Time.utc(2021, 4, 30))
    end

    # July has 31 days, so the anniversary stays on the subscription day instead of following the
    # month end.
    it "keeps the anniversary on the subscription day in a longer month" do
      expect(period_on(DateTime.new(2021, 8, 15), subscription:).first).to eq(Time.utc(2021, 7, 30))
    end

    it "returns periods that meet without overlapping" do
      closing = period_on(DateTime.new(2021, 7, 29), subscription:)
      opening = period_on(DateTime.new(2021, 7, 30), subscription:)

      expect(closing.last).to eq(Time.utc(2021, 7, 29, 23, 59, 59))
      expect(opening.first).to eq(Time.utc(2021, 7, 30))
    end
  end

  context "with a semiannual subscription starting on the end of a 30-day month" do
    let(:subscription) { subscribe_on(DateTime.new(2021, 4, 30), interval: :semiannual) }

    # June is neither a billing month nor the anniversary, yet its month end used to open a period.
    it "ignores month ends outside a billing month" do
      expect(period_on(DateTime.new(2021, 6, 30), subscription:).first).to eq(Time.utc(2021, 4, 30))
    end

    # October has 31 days, so the anniversary stays on the subscription day.
    it "keeps the anniversary on the subscription day in a longer month" do
      expect(period_on(DateTime.new(2021, 11, 15), subscription:).first).to eq(Time.utc(2021, 10, 30))
    end
  end
end
