# frozen_string_literal: true

module BillingPeriods
  # One billing period for a subscription rate card — May 1 to May 31.
  #
  # It normally becomes one Cycle. It becomes several only when a rate's effective_from falls
  # strictly INSIDE it: each slice is priced with the rate in force over it, and `index` does
  # not advance — the customer is still in their first period, it just costs two prices across
  # it. Rate phases never split one; they change how long periods are, not what a period holds.
  #
  # `full_days` is the whole span: a card starting mid-period is cut short but still prorates
  # against the full month.
  Period = Data.define(
    :index,
    :starts_at,
    :ends_at,
    :next_billing_at,
    :rate_phase,
    :full_days,
    :timezone
  ) do
    def rate_override
      rate_phase&.rate_override
    end

    # What share of this period a window covers: 1 when it spans the period, less when a rate
    # change, a late start or a cancellation cuts it short, 0 when it ends before it starts.
    def share_of(from, to)
      return 1 if full_days.zero?

      Utils::Datetime.date_diff_with_timezone(from, to, timezone).fdiv(full_days).clamp(0, 1)
    end
  end
end
