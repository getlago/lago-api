# frozen_string_literal: true

namespace :invoices do
  desc 'Generate Number for Invoices'
  task generate_number: :environment do
    Invoice.order(:created_at).find_each(&:save)
  end

  desc 'Populate invoice_subscriptions join table'
  task handle_subscriptions: :environment do
    Invoice.order(:created_at).find_each do |invoice|
      subscription_id = invoice&.subscription_id
      next unless subscription_id

      invoice_subscription = InvoiceSubscription.find_by(
        invoice_id: invoice.id,
        subscription_id:,
      )

      next if invoice_subscription

      InvoiceSubscription.create!(invoice_id: invoice.id, subscription_id:, timestamp: Time.current)
    end
  end

  desc 'Fill missing customer_id'
  task fill_customer: :environment do
    Invoice.where(customer_id: nil).find_each do |invoice|
      invoice.update!(customer_id: invoice.subscriptions&.first&.customer_id)
    end
  end

  desc 'Fill invoice Taxes rate'
  task fill_taxes_rate: :environment do
    Invoice.where(taxes_rate: nil).find_each do |invoice|
      invoice.update!(
        taxes_rate: (invoice.taxes_amount_cents.fdiv(invoice.amount_cents) * 100).round(2),
      )
    end
  end

  desc 'Set currency to fees'
  task set_currency_to_fees: :environment do
    Invoice.find_each do |invoice|
      invoice.fees.each do |fee|
        fee.update(
          amount_currency: invoice.currency,
          vat_amount_currency: invoice.currency,
        )
      end
    end
  end
end
