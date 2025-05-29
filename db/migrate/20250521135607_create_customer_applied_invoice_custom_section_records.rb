# frozen_string_literal: true

class CreateCustomerAppliedInvoiceCustomSectionRecords < ActiveRecord::Migration[8.0]
  def up
    Customer::AppliedInvoiceCustomSection.insert_all( # rubocop:disable Rails/SkipsModelValidations
      InvoiceCustomSectionSelection.where.not(customer_id: nil).includes(:customer).map do |selection|
        {
          id: selection.id,
          organization_id: selection.customer.organization_id,
          billing_entity_id: selection.customer.billing_entity_id,
          customer_id: selection.customer_id,
          invoice_custom_section_id: selection.invoice_custom_section_id,
          created_at: selection.created_at,
          updated_at: selection.updated_at
        }
      end
    )
  end

  def down
    Customer::AppliedInvoiceCustomSection.delete_all
  end
end
