# frozen_string_literal: true

namespace :invoices do
  desc "Generate Number for Invoices"
  task generate_number: :environment do
    Invoice.order(:created_at).find_each(&:save)
  end

  desc "Populate invoice_subscriptions join table"
  task handle_subscriptions: :environment do
    Invoice.order(:created_at).find_each do |invoice|
      subscription_id = invoice&.subscription_id
      next unless subscription_id

      invoice_subscription = InvoiceSubscription.find_by(
        invoice_id: invoice.id,
        subscription_id:
      )

      next if invoice_subscription

      InvoiceSubscription.create!(invoice_id: invoice.id, subscription_id:, timestamp: Time.current)
    end
  end

  desc "Fill missing customer_id"
  task fill_customer: :environment do
    Invoice.where(customer_id: nil).find_each do |invoice|
      invoice.update!(customer_id: invoice.subscriptions&.first&.customer_id)
    end
  end

  desc "Fill invoice Taxes rate"
  task fill_taxes_rate: :environment do
    Invoice.where(taxes_rate: nil).find_each do |invoice|
      invoice.update!(
        taxes_rate: (invoice.taxes_amount_cents.fdiv(invoice.amount_cents) * 100).round(2)
      )
    end
  end

  desc "Fill expected_finalization_date"
  task fill_expected_finalization_date: :environment do
    Invoice.in_batches(of: 10_000).update_all("expected_finalization_date = COALESCE(expected_finalization_date, issuing_date)") # rubocop:disable Rails/SkipsModelValidations
  end

  desc "Fix non-subscription invoices that used grace_period even though they should not"
  task fix_non_subscription_issuing_date: :environment do
    invoices = Invoice.finalized.where.not(invoice_type: :subscription).where("created_at >= DATE '2025-12-11' AND issuing_date > created_at")

    invoices.find_each do |invoice|
      issuing_date = invoice.created_at.in_time_zone(invoice.customer.applicable_timezone).to_date

      invoice.update(
        issuing_date:,
        payment_due_date: (issuing_date + invoice.customer.applicable_net_payment_term.days).to_date,
        expected_finalization_date: issuing_date
      )

      if invoice.file.url
        invoice.file.purge
        Invoices::GeneratePdfJob.perform_later(invoice)
      end
    end
  end
end
