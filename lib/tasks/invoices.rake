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
        subscription_id: subscription_id
      )

      next if invoice_subscription

      InvoiceSubscription.create!(invoice_id: invoice.id, subscription_id: subscription_id)
    end
  end

  desc 'Fill missing customer_id'
  task fill_customer: :environment do
    Invoice.where(customer_id: nil).find_each do |invoice|
      invoice.update!(customer_id: invoice.subscriptions&.first&.customer_id)
    end
  end
end
