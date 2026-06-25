# frozen_string_literal: true

require "rails_helper"

# Proves the new BillingPeriods::DatesService reproduces the boundaries of the
# legacy Subscriptions::Dates::* services for the same dates.
#
# Mapping:
#   legacy :calendar    -> anchor = subscription_at.beginning_of_month / _week
#   legacy :anniversary -> anchor = subscription_at (the subscription day/weekday)
#   legacy from_datetime == new period_from ; legacy to_datetime == new period_to
RSpec.describe "BillingPeriods::DatesService legacy parity", type: :service do
  let(:timezone) { "UTC" }
  let(:interval_count) { 1 }
  let(:customer) { create(:customer, timezone:) }
  let(:plan) { create(:plan, interval: plan_interval, pay_in_advance: false) }
  let(:subscription) do
    create(:subscription, plan:, customer:, subscription_at:, started_at: subscription_at, billing_time:)
  end

  def new_engine(billing_at)
    BillingPeriods::DatesService.call(
      billing_anchor_date: anchor,
      interval_count:,
      interval_unit:,
      billing_timing: :arrears,
      timezone:,
      billing_at:
    )
  end

  # calendar anchoring grain per legacy interval (quarterly -> calendar quarters,
  # semiannual -> calendar halves anchored on Jan 1 / Jul 1, etc.)
  def anchor
    date = subscription_at.to_date
    return date if billing_time == :anniversary

    date.public_send("beginning_of_#{calendar_grain}")
  end

  shared_examples "matches the legacy engine" do |billing_ats|
    it "produces identical boundaries" do
      billing_ats.each do |at|
        old = legacy_class.new(subscription, at, false)
        new = new_engine(at)

        expect(new.period_from).to match_datetime(old.from_datetime),
          -> { "from mismatch @ #{at}: new=#{new.period_from} old=#{old.from_datetime}" }
        expect(new.period_to).to match_datetime(old.to_datetime),
          -> { "to mismatch @ #{at}: new=#{new.period_to} old=#{old.to_datetime}" }
      end
    end
  end

  describe "monthly" do
    let(:plan_interval) { :monthly }
    let(:interval_unit) { :month }
    let(:calendar_grain) { :month }
    let(:legacy_class) { Subscriptions::Dates::MonthlyService }

    context "calendar" do
      let(:billing_time) { :calendar }
      let(:subscription_at) { Time.zone.parse("2021-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-03-01"), Time.zone.parse("2022-04-01"), Time.zone.parse("2022-07-01")]

      context "with a customer timezone" do
        let(:timezone) { "America/New_York" }

        include_examples "matches the legacy engine", [Time.zone.parse("2022-03-01"), Time.zone.parse("2022-06-01")]
      end
    end

    context "anniversary" do
      let(:billing_time) { :anniversary }
      let(:subscription_at) { Time.zone.parse("2021-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-03-02"), Time.zone.parse("2022-04-02")]
    end

    context "anniversary, month-end anchor" do
      let(:billing_time) { :anniversary }
      let(:subscription_at) { Time.zone.parse("2021-01-31") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-02-28"), Time.zone.parse("2022-03-31")]
    end
  end

  describe "weekly" do
    let(:plan_interval) { :weekly }
    let(:interval_unit) { :week }
    let(:calendar_grain) { :week }
    let(:legacy_class) { Subscriptions::Dates::WeeklyService }

    context "calendar" do
      let(:billing_time) { :calendar }
      let(:subscription_at) { Time.zone.parse("2021-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-03-07"), Time.zone.parse("2022-03-09"), Time.zone.parse("2022-03-21")]

      context "with a customer timezone" do
        let(:timezone) { "America/New_York" }

        include_examples "matches the legacy engine", [Time.zone.parse("2022-03-07"), Time.zone.parse("2022-03-21")]
      end
    end

    context "anniversary" do
      let(:billing_time) { :anniversary }
      let(:subscription_at) { Time.zone.parse("2021-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-03-09"), Time.zone.parse("2022-03-16")]
    end
  end

  describe "yearly" do
    let(:plan_interval) { :yearly }
    let(:interval_unit) { :year }
    let(:calendar_grain) { :year }
    let(:legacy_class) { Subscriptions::Dates::YearlyService }

    context "calendar" do
      let(:billing_time) { :calendar }
      let(:subscription_at) { Time.zone.parse("2019-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-01-01"), Time.zone.parse("2023-01-01")]

      context "with a customer timezone" do
        let(:timezone) { "America/New_York" }

        include_examples "matches the legacy engine", [Time.zone.parse("2022-01-01")]
      end
    end

    context "anniversary" do
      let(:billing_time) { :anniversary }
      let(:subscription_at) { Time.zone.parse("2020-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-02-02"), Time.zone.parse("2023-02-02")]
    end
  end

  describe "quarterly (month interval, count 3)" do
    let(:plan_interval) { :quarterly }
    let(:interval_unit) { :month }
    let(:interval_count) { 3 }
    let(:calendar_grain) { :quarter }
    let(:legacy_class) { Subscriptions::Dates::QuarterlyService }

    context "calendar" do
      let(:billing_time) { :calendar }
      let(:subscription_at) { Time.zone.parse("2021-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-07-01"), Time.zone.parse("2022-10-01")]

      context "with a customer timezone" do
        let(:timezone) { "America/New_York" }

        include_examples "matches the legacy engine", [Time.zone.parse("2022-07-01")]
      end
    end

    context "anniversary" do
      let(:billing_time) { :anniversary }
      let(:subscription_at) { Time.zone.parse("2021-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-05-02"), Time.zone.parse("2022-08-02")]
    end
  end

  describe "semiannual (month interval, count 6)" do
    let(:plan_interval) { :semiannual }
    let(:interval_unit) { :month }
    let(:interval_count) { 6 }
    let(:calendar_grain) { :year }
    let(:legacy_class) { Subscriptions::Dates::SemiannualService }

    context "calendar" do
      let(:billing_time) { :calendar }
      let(:subscription_at) { Time.zone.parse("2021-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-07-01"), Time.zone.parse("2023-01-01")]
    end

    context "anniversary" do
      let(:billing_time) { :anniversary }
      let(:subscription_at) { Time.zone.parse("2021-02-02") }

      include_examples "matches the legacy engine", [Time.zone.parse("2022-08-02"), Time.zone.parse("2023-02-02")]
    end
  end
end
