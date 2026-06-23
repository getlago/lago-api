# frozen_string_literal: true

# Interval-agnostic invariants of BillingPeriods::DatesService that must hold for
# every interval, anchor and timezone. The including example group must define:
#   billing_anchor_date, interval_count, interval_unit, timezone, billing_at
#
# Periods are returned with an inclusive end (period_to = end_of_day of the final
# day), and next_billing_at is the next boundary (beginning of day).
RSpec.shared_examples "billing period boundaries" do
  let(:arrears_result) do
    BillingPeriods::DatesService.call(
      billing_anchor_date:, interval_count:, interval_unit:,
      billing_timing: :arrears, timezone:, billing_at:
    )
  end

  let(:advance_result) do
    BillingPeriods::DatesService.call(
      billing_anchor_date:, interval_count:, interval_unit:,
      billing_timing: :advance, timezone:, billing_at:
    )
  end

  it "resolves a non-empty period for each timing" do
    expect(arrears_result.period_to).to be > arrears_result.period_from
    expect(advance_result.period_to).to be > advance_result.period_from
  end

  it "bills next at the same instant regardless of timing" do
    expect(arrears_result.next_billing_at).to eq(advance_result.next_billing_at)
  end

  it "bills at the boundary just after the period it closes" do
    expect(arrears_result.next_billing_at).to be > arrears_result.period_to
    expect(advance_result.next_billing_at).to be > advance_result.period_to
  end

  it "tiles consecutively: the advance period starts right after the arrears period ends" do
    expect(advance_result.period_from).to be > arrears_result.period_to
    expect(advance_result.period_from - arrears_result.period_to).to be < 1.second
  end
end
