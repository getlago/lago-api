# frozen_string_literal: true

class MigrateOrganizationTaxes < ActiveRecord::Migration[7.0]
  # NOTE: redifine models to prevent schema issue in the future
  class Organization < ApplicationRecord; end

  class Tax < ApplicationRecord; end

  class Customer < ApplicationRecord; end

  class CustomersTax < ApplicationRecord; end

  class FeesTax < ApplicationRecord; end

  class InvoicesTax < ApplicationRecord; end

  class CreditNotesTax < ApplicationRecord; end

  def change
    reversible do |dir|
      dir.up do
        # NOTE: migrate organizations taxes
        Organization.where('vat_rate > 0').find_each do |organization|
          Tax.create_with(
            organization_id: organization.id,
            name: 'Tax',
            rate: organization.vat_rate,
            applied_to_organization: true
          ).find_or_create_by!(code: "tax_#{organization.vat_rate}")
        end

        # NOTE: migrate customers taxes
        Customer.where.not(vat_rate: nil).find_each do |customer|
          tax = Tax.create_with(
            name: 'Tax',
            rate: customer.vat_rate
          ).find_or_create_by!(
            organization_id: customer.organization_id,
            code: "tax_#{customer.vat_rate}"
          )

          CustomersTax.find_or_create_by!(
            customer_id: customer.id,
            tax_id: tax.id
          )
        end

        # NOTE: migrate fees taxes
        sql = <<-SQL
          WITH existing_fees_taxes AS (
            SELECT
              fees.id AS fee_id
            FROM fees
              LEFT JOIN fees_taxes ON fees.id = fees_taxes.fee_id
            GROUP BY fees.id
            --HAVING COUNT(fees_taxes.id) = 0
          )

          SELECT
            COALESCE(invoices.organization_id, customers.organization_id) AS organization_id,
            fees.id AS fee_id,
            fees.taxes_rate AS taxes_rate,
            fees.amount_currency AS currency,
            fees.taxes_amount_cents AS taxes_amount_cents
          FROM existing_fees_taxes
            INNER JOIN
            fees ON existing_fees_taxes.fee_id = fees.id
            LEFT JOIN invoices ON fees.invoice_id = invoices.id
            LEFT JOIN subscriptions ON fees.subscription_id = subscriptions.id
            LEFT JOIN customers ON subscriptions.customer_id = customers.id
          WHERE
            fees.taxes_amount_cents > 0
            OR (fees.taxes_amount_cents = 0 AND customers.vat_rate IS NOT NULL)
        SQL

        indexed_rows = ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, result|
          result[row['organization_id']] ||= {}
          result[row['organization_id']][row['taxes_rate']] ||= []
          result[row['organization_id']][row['taxes_rate']] << row
        end

        indexed_rows.each do |organization_id, taxes|
          taxes.each do |tax_rate, rows|
            tax = Tax.create_with(
              name: 'Tax',
              rate: tax_rate
            ).find_or_create_by!(
              organization_id:,
              code: "tax_#{tax_rate}"
            )

            rows.each do |row|
              FeesTax.find_or_create_by!(
                fee_id: row['fee_id'],
                tax_id: tax.id,
                tax_description: tax.description,
                tax_code: tax.code,
                tax_name: tax.name,
                tax_rate: tax.rate,
                amount_currency: row['currency'],
                amount_cents: row['taxes_amount_cents']
              )
            end
          end
        end

        # NOTE: migrate invoices taxes
        sql = <<-SQL
          WITH existing_invoices_taxes AS (
            SELECT invoices.id AS invoice_id
            FROM invoices
              LEFT JOIN invoices_taxes ON invoices.id = invoices_taxes.invoice_id
            GROUP BY invoices.id
            HAVING COUNT(invoices_taxes.id) = 0
          )

          SELECT
            invoices.organization_id,
            invoices.id AS invoice_id,
            invoices.taxes_rate AS taxes_rate,
            invoices.currency AS currency,
            invoices.taxes_amount_cents AS taxes_amount_cents
          FROM existing_invoices_taxes
            INNER JOIN invoices ON existing_invoices_taxes.invoice_id = invoices.id
            INNER JOIN customers ON invoices.customer_id = customers.id
          WHERE
            invoices.taxes_amount_cents > 0
            OR (invoices.taxes_amount_cents = 0 AND customers.vat_rate IS NOT NULL)
        SQL

        indexed_rows = ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, result|
          result[row['organization_id']] ||= {}
          result[row['organization_id']][row['taxes_rate']] ||= []
          result[row['organization_id']][row['taxes_rate']] << row
        end

        indexed_rows.each do |organization_id, taxes|
          taxes.each do |tax_rate, rows|
            tax = Tax.create_with(
              name: 'Tax',
              rate: tax_rate
            ).find_or_create_by!(
              organization_id:,
              code: "tax_#{tax_rate}"
            )

            rows.each do |row|
              InvoicesTax.find_or_create_by!(
                invoice_id: row['invoice_id'],
                tax_id: tax.id,
                tax_description: tax.description,
                tax_code: tax.code,
                tax_name: tax.name,
                tax_rate: tax.rate,
                amount_currency: row['currency'],
                amount_cents: row['taxes_amount_cents']
              )
            end
          end
        end

        # NOTE: migrate credit notes taxes
        sql = <<-SQL
          WITH existing_credit_notes_taxes AS (
            SELECT credit_notes.id AS credit_note_id
            FROM credit_notes
              LEFT JOIN credit_notes_taxes ON credit_notes.id = credit_notes_taxes.credit_note_id
            GROUP BY credit_notes.id
            HAVING COUNT(credit_notes_taxes.id) = 0
          )

          SELECT
            invoices.organization_id,
            credit_notes.id AS credit_note_id,
            invoices.taxes_rate AS taxes_rate,
            invoices.currency AS currency,
            credit_notes.taxes_amount_cents AS taxes_amount_cents
          FROM existing_credit_notes_taxes
            INNER JOIN credit_notes ON existing_credit_notes_taxes.credit_note_id = credit_notes.id
            INNER JOIN invoices ON credit_notes.invoice_id = invoices.id
            INNER JOIN customers ON invoices.customer_id = customers.id
          WHERE
            credit_notes.taxes_amount_cents > 0
            OR (credit_notes.taxes_amount_cents = 0 AND customers.vat_rate IS NOT NULL)
        SQL

        indexed_rows = ApplicationRecord.connection.select_all(sql).each_with_object({}) do |row, result|
          result[row['organization_id']] ||= {}
          result[row['organization_id']][row['taxes_rate']] ||= []
          result[row['organization_id']][row['taxes_rate']] << row
        end

        indexed_rows.each do |organization_id, taxes|
          taxes.each do |tax_rate, rows|
            tax = Tax.create_with(
              name: 'Tax',
              rate: tax_rate
            ).find_or_create_by!(
              organization_id:,
              code: "tax_#{tax_rate}"
            )

            rows.each do |row|
              CreditNotesTax.find_or_create_by!(
                credit_note_id: row['credit_note_id'],
                tax_id: tax.id,
                tax_description: tax.description,
                tax_code: tax.code,
                tax_name: tax.name,
                tax_rate: tax.rate,
                amount_currency: row['currency'],
                amount_cents: row['taxes_amount_cents']
              )
            end
          end
        end
      end
    end
  end
end
