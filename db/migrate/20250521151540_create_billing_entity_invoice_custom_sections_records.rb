# frozen_string_literal: true

class CreateBillingEntityInvoiceCustomSectionsRecords < ActiveRecord::Migration[8.0]
  def up
    BillingEntity::AppliedInvoiceCustomSection.insert_all( # rubocop:disable Rails/SkipsModelValidations
      InvoiceCustomSectionSelection
        .where.not(organization_id: nil)
        .includes(organization: :default_billing_entity)
        .map do |selection|
          {
            id: selection.id,
            organization_id: selection.organization_id,
            billing_entity_id: selection.organization.default_billing_entity.id,
            invoice_custom_section_id: selection.invoice_custom_section_id,
            created_at: selection.created_at,
            updated_at: selection.updated_at
          }
        end
    )
  end

  def down
    BillingEntity::AppliedInvoiceCustomSection.delete_all
  end
end
