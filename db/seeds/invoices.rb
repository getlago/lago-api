# frozen_string_literal: true

# NOTE: Generate invoices for the customers
Subscription.all.find_each do |subscription|
  Invoices::SubscriptionService.new(
    subscriptions: [subscription],
    timestamp: Time.zone.now - 2.months,
    recurring: true,
  ).create
end

Invoice.all.find_each do |invoice|
  fee = invoice.fees.sample
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
    vat_amount_currency: fee.amount_currency,
    vat_amount_cents: fee.vat_amount_cents,
  )

  credit_note.items.create!(
    fee:,
    amount_cents: amount,
    precise_amount_cents: amount,
    amount_currency: fee.amount_currency,
  )
end
