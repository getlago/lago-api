# frozen_string_literal: true

class InvoiceCustomSectionsQuery < BaseQuery
  def call
    invoice_custom_sections = paginate(base_scope)
    invoice_custom_sections = apply_consistent_ordering(invoice_custom_sections)

    result.invoice_custom_sections = invoice_custom_sections
    result
  end

  private

  def base_scope
    InvoiceCustomSection.where(organization:)
  end
end
