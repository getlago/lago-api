# frozen_string_literal: true

class AddFieldsForNewDocumentNumbering < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :organizations, bulk: true do |t|
        t.integer :document_numbering, default: 0, null: false
        t.string :document_number_prefix, null: true
      end
      add_column :invoices, :organization_sequential_id, :integer, null: false, default: 0

      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE organizations
          SET document_number_prefix = UPPER(CAST(SUBSTRING(name, 1, 3) AS VARCHAR)) || '-' || UPPER(CAST(RIGHT(id::TEXT, 4) AS VARCHAR))
          WHERE document_number_prefix IS NULL;
          SQL

          execute <<-SQL
					WITH ordered_organization_invoices AS (
				    SELECT
              invoices.id AS invoice_id,
              ROW_NUMBER() OVER (PARTITION BY invoices.organization_id, DATE_PART('month', invoices.created_at) ORDER BY invoices.created_at ASC) AS rn
				    FROM invoices
					)

					UPDATE invoices
					SET organization_sequential_id = ordered_organization_invoices.rn
					FROM ordered_organization_invoices
					WHERE invoices.organization_sequential_id = 0
            AND ordered_organization_invoices.invoice_id = invoices.id;
          SQL
        end
      end

      change_column_null :organizations, :document_number_prefix, null: false
    end
  end
end
