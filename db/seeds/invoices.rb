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

Invoice.all.find_each do |invoice|
  fee = invoice.fees.sample
  next if fee.nil?

  amount = fee.amount_cents / 2
  next if amount.zero?

  credit_note = CreditNote.create!(
    customer: invoice.customer,
    invoice:,
    credit_amount_cents: amount,
    credit_amount_currency: fee.amount_currency,
    credit_status: :available,
    balance_amount_cents: amount,
    balance_amount_currency: fee.amount_currency,
    reason: :other,
    total_amount_cents: amount,
    total_amount_currency: fee.amount_currency,
    issuing_date: Time.current.to_date,
    taxes_amount_cents: fee.taxes_amount_cents
  )

  credit_note.items.create!(
    fee:,
    amount_cents: amount,
    precise_amount_cents: amount,
    amount_currency: fee.amount_currency
  )
end
