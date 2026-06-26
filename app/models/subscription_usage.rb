# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

SubscriptionUsage = Struct.new(
  :from_datetime,
  :to_datetime,
  :issuing_date,
  :currency,
  :amount_cents,
  :total_amount_cents,
  :taxes_amount_cents,
  :fees
)
