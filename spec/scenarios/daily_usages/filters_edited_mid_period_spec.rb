# frozen_string_literal: true

require "rails_helper"

# A charge's filters are edited during an open billing period. Current usage is recomputed over the whole
# period with the new filters, so the daily usage written after the edit holds filters that did not exist
# the day before. Filter-level diffs must still add up to the charge-level diff, and summing the daily
# diffs of the period must give the period's usage, for the charge and for its filters.
describe "Daily Usages: charge filters edited mid-period", :premium do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["revenue_analytics"]) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "characters", field_name: "count") }
  let(:metric_filter) { create(:billable_metric_filter, billable_metric:, key: "model", values: %w[a b c]) }
  let(:subscription) { organization.subscriptions.sole }

  let(:initial_filters) do
    [{invoice_display_name: "Models", properties: {amount: "1"}, values: {model: %w[a b]}}]
  end

  before do
    metric_filter

    travel_to(DateTime.new(2025, 3, 1, 1)) do
      create_plan({
        name: "Startup",
        code: "startup",
        interval: "monthly",
        amount_cents: 0,
        amount_currency: "EUR",
        pay_in_advance: false,
        charges: [plan_charge(initial_filters)]
      })

      create_subscription({
        external_customer_id: customer.external_id,
        external_id: "sub_startup",
        plan_code: "startup",
        billing_time: "calendar"
      })
    end
  end

  def plan_charge(filters)
    {
      billable_metric_id: billable_metric.id,
      charge_model: "standard",
      code: "characters_charge",
      pay_in_advance: false,
      properties: {amount: "2"},
      filters:
    }
  end

  def edit_filters(filters)
    plan = organization.plans.find_by(code: "startup")

    update_plan(plan, {
      name: "Startup", code: "startup", interval: "monthly", amount_cents: 0,
      amount_currency: "EUR", pay_in_advance: false,
      charges: [plan_charge(filters).merge(id: plan.charges.sole.id)]
    })
  end

  def send_usage(day, counts)
    travel_to(DateTime.new(2025, 3, day, 12)) do
      counts.each do |model, count|
        create_event({
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          properties: {model:, count:}
        })
      end
    end
  end

  def compute_daily_usage(day)
    travel_to(DateTime.new(2025, 3, day + 1, 0, 10)) { perform_usage_update }
  end

  def daily_usage(day)
    subscription.daily_usages.find_by!(usage_date: Date.new(2025, 3, day))
  end

  def charge_diff(daily_usage)
    daily_usage.usage_diff.fetch("charges_usage").sole
  end

  def filters_total(charge_usage, field)
    charge_usage.fetch("filters").sum { |filter| BigDecimal(filter[field].to_s) }
  end

  def expect_filters_to_add_up(daily_usage)
    charge = charge_diff(daily_usage)

    %w[amount_cents units events_count].each do |field|
      expect(filters_total(charge, field)).to eq(BigDecimal(charge[field].to_s)), "#{field} on #{daily_usage.usage_date}"
    end
  end

  def run_period(edit_day:, new_filters:)
    (2..5).each do |day|
      edit_filters(new_filters) if day == edit_day
      send_usage(day, {"a" => 10, "b" => 5, "c" => 1})
      compute_daily_usage(day)
    end
  end

  shared_examples "consistent daily usage diffs" do |edit_day:|
    it "keeps filter diffs consistent with the charge diff on every day" do
      (2..5).each { |day| expect_filters_to_add_up(daily_usage(day)) }
    end

    it "reports only the day's usage on the day after the edit" do
      expect(charge_diff(daily_usage(edit_day))["amount_cents"]).to eq(daily_amount_cents)
      expect(filters_total(charge_diff(daily_usage(edit_day)), "amount_cents")).to eq(daily_amount_cents)
    end

    it "sums the daily filter diffs of the period to the period's usage" do
      period_usage = daily_usage(5).usage.fetch("charges_usage").sole
      summed_filters = (2..5).sum { |day| filters_total(charge_diff(daily_usage(day)), "amount_cents") }

      expect(summed_filters).to eq(period_usage["amount_cents"])
      expect(summed_filters).to eq(4 * daily_amount_cents)
    end

    context "when the daily usage was diffed before the fix" do
      let(:affected) { daily_usage(edit_day) }
      let!(:expected_usage_diff) { affected.usage_diff }
      let!(:previous_day_usage_diff) { daily_usage(edit_day - 1).usage_diff }

      before do
        # Reproduces the diff written before the fix: filters without a match in the previous day
        # kept their period-to-date values.
        previous_values = daily_usage(edit_day - 1).usage.fetch("charges_usage").sole.fetch("filters").map { |f| f["values"] }
        corrupted = affected.usage_diff.deep_dup
        corrupted.fetch("charges_usage").sole.fetch("filters").each do |filter|
          next if previous_values.include?(filter["values"])

          cumulative = affected.usage.fetch("charges_usage").sole.fetch("filters").find { |f| f["values"] == filter["values"] }
          filter.merge!(cumulative.slice("amount_cents", "units", "events_count"))
        end
        affected.update!(usage_diff: corrupted)
      end

      it "is detected and restored by the recompute service" do
        dry_run = DailyUsages::RecomputeDiffsService.call!(subscription:, from_date: Date.new(2025, 3, 1), dry_run: true)
        expect(dry_run.daily_usages).to eq([affected])
        expect(affected.reload.usage_diff).not_to eq(expected_usage_diff)

        DailyUsages::RecomputeDiffsService.call!(subscription:, from_date: Date.new(2025, 3, 1))

        expect(affected.reload.usage_diff).to eq(expected_usage_diff)
        expect(daily_usage(edit_day - 1).usage_diff).to eq(previous_day_usage_diff)
      end
    end
  end

  # a: 10 units, b: 5 units, c: 1 unit per day. Filtered models are priced 1 EUR, the rest 2 EUR.
  context "when a value is moved out of a filter into a new filter" do
    let(:daily_amount_cents) { (10 + 5) * 100 + 1 * 200 }

    before do
      run_period(
        edit_day: 4,
        new_filters: [
          {invoice_display_name: "Model b", properties: {amount: "1"}, values: {model: %w[b]}},
          {invoice_display_name: "Model a", properties: {amount: "1"}, values: {model: %w[a]}}
        ]
      )
    end

    it_behaves_like "consistent daily usage diffs", edit_day: 4
  end

  context "when a value is removed from a filter and falls back into the default price" do
    # From the edit, model a is priced 2 EUR for the whole period, as current usage is recomputed
    # with the new filters. The day of the edit absorbs that re-pricing of the earlier days.
    let(:daily_amount_cents) { 5 * 100 + (10 + 1) * 200 }

    before do
      run_period(
        edit_day: 4,
        new_filters: [{invoice_display_name: "Models", properties: {amount: "1"}, values: {model: %w[b]}}]
      )
    end

    it "keeps filter diffs consistent with the charge diff on every day" do
      (2..5).each { |day| expect_filters_to_add_up(daily_usage(day)) }
    end

    it "sums the daily diffs of the period to the period's usage" do
      period_usage = daily_usage(5).usage.fetch("charges_usage").sole
      summed_charge = (2..5).sum { |day| charge_diff(daily_usage(day))["amount_cents"] }
      summed_filters = (2..5).sum { |day| filters_total(charge_diff(daily_usage(day)), "amount_cents") }

      expect(summed_charge).to eq(period_usage["amount_cents"])
      expect(summed_filters).to eq(period_usage["amount_cents"])
    end
  end

  context "when filters are not edited" do
    let(:daily_amount_cents) { (10 + 5) * 100 + 1 * 200 }

    before { run_period(edit_day: nil, new_filters: initial_filters) }

    it "reports each day's usage on its own day" do
      (2..5).each do |day|
        expect(charge_diff(daily_usage(day))["amount_cents"]).to eq(daily_amount_cents)
        expect_filters_to_add_up(daily_usage(day))
      end
    end

    it "does not flag any daily usage for recompute" do
      result = DailyUsages::RecomputeDiffsService.call!(subscription:, from_date: Date.new(2025, 3, 1), dry_run: true)
      expect(result.daily_usages).to be_empty
    end
  end
end
