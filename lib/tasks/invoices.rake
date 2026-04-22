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

  desc "Touch invoices.updated_at to MAX(invoice_metadata.updated_at) so Prequel re-syncs stale metadata"
  task :backfill_metadata_updated_at, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id]
    abort "Missing organization_id argument\n\nUsage: rake invoices:backfill_metadata_updated_at[organization_id]" if organization_id.blank?

    batch_size = (ENV["BATCH_SIZE"] || 1_000).to_i
    total_limit = (ENV["TOTAL_LIMIT"] || 10_000).to_i
    abort "BATCH_SIZE must be positive" if batch_size <= 0
    abort "TOTAL_LIMIT must be positive" if total_limit <= 0

    # Interpolated directly since these are trusted integer constants, not user input.
    visible_statuses_sql = Invoice::VISIBLE_STATUS.values.join(",")
    total_updated = 0

    puts "Starting backfill for organization #{organization_id} (batch_size: #{batch_size}, total_limit: #{total_limit})..."

    loop do
      remaining_budget = total_limit - total_updated
      break if remaining_budget <= 0

      effective_limit = [batch_size, remaining_budget].min

      update_sql = <<~SQL.squish
        UPDATE invoices
        SET updated_at = stale.max_metadata_updated_at
        FROM (
          SELECT invoices.id, MAX(im.updated_at) AS max_metadata_updated_at
          FROM invoices
          JOIN invoice_metadata im ON im.invoice_id = invoices.id
          WHERE invoices.organization_id = $1
            AND invoices.status IN (#{visible_statuses_sql})
          GROUP BY invoices.id
          HAVING MAX(im.updated_at) > invoices.updated_at
          LIMIT #{effective_limit}
        ) AS stale
        WHERE invoices.id = stale.id
          AND invoices.updated_at < stale.max_metadata_updated_at
      SQL

      rows = ActiveRecord::Base.connection.exec_update(update_sql, "BackfillInvoiceMetadataUpdatedAt", [organization_id])
      total_updated += rows
      puts "  Batch updated: #{rows} rows (total: #{total_updated})"
      break if rows < effective_limit
    end

    remaining = Invoice
      .joins("JOIN invoice_metadata im ON im.invoice_id = invoices.id")
      .where(organization_id: organization_id, status: Invoice::VISIBLE_STATUS.keys)
      .where("invoices.updated_at < im.updated_at")
      .distinct
      .count

    puts "Done. Total updated: #{total_updated}. Remaining stale invoices: #{remaining}."
  end
end
