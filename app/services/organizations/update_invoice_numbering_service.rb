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
        organization_invoices_count = organization.invoices.non_self_billed.with_generated_number.count
        organization.invoices.order(created_at: :desc).first&.update!(organization_sequential_id: organization_invoices_count)
      end

      organization.document_numbering = document_numbering

      result
    end

    private

    attr_reader :organization, :document_numbering
  end
end
