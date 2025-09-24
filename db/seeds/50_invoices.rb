# frozen_string_literal: true

# NOTE: Generate invoices for the customers
Subscription.all.find_each do |subscription|
  invoice_count = (Time.current - subscription.subscription_at).fdiv(1.month).round

  (0..invoice_count).each do |offset|
    Invoices::SubscriptionService.call(
      subscriptions: [subscription],
      timestamp: Time.current - offset.months + 1.day,
      invoicing_reason: :subscription_periodic
    )
  end
end
