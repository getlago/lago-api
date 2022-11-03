# frozen_string_literal: true

# NOTE: Generate invoices for the customers
Subscription.all.find_each do |subscription|
  Invoices::CreateService.new(
    subscriptions: [subscription],
    timestamp: Time.zone.now - 2.months,
  ).create
end

Invoice.all.find_each do |invoice|
  fee = invoice.fees.sample
  amount = fee.amount_cents / 2
  next if amount.zero?

  credit_note = CreditNote.create!(
    customer: invoice.customer,
    invoice: invoice,
    credit_amount_cents: amount,
    credit_amount_currency: fee.amount_currency,
    credit_status: :available,
    balance_amount_cents: amount,
    balance_amount_currency: fee.amount_currency,
    reason: :other,
    total_amount_cents: amount,
    total_amount_currency: fee.amount_currency,
  )

  credit_note.items.create!(
    fee: fee,
    credit_amount_cents: amount,
    credit_amount_currency: fee.amount_currency,
  )
end
