# frozen_string_literal: true

module Organizations
  class UpdateInvoiceNumberingService < BaseService
    Result = BaseResult[:organization]

    def initialize(organization:, document_numbering:)
      @organization = organization
      @document_numbering = document_numbering
      super
    end

    def call
      result.organization = organization

      return result if organization.document_numbering == document_numbering

      if organization.per_customer? && document_numbering == "per_organization"
        last_invoice = organization.invoices.non_self_billed.with_generated_number.order(created_at: :desc).first

        if last_invoice
          organization_invoices_count = organization.invoices.non_self_billed.with_generated_number.count
          last_invoice.update!(organization_sequential_id: organization_invoices_count)
        end
      end

      organization.document_numbering = document_numbering

      result
    end

    private

    attr_reader :organization, :document_numbering
  end
end
