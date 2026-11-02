# frozen_string_literal: true

module Invoices
  class GenerateXmlService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:, context: nil)
      @invoice = invoice
      @context = context

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") if invoice.blank?
      return result.not_allowed_failure!(code: "is_draft") if invoice.draft?

      if should_generate_xml?
        generate_xml
      end

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :context

    def generate_xml
      I18n.with_locale(invoice.customer.preferred_document_locale) do
        xml_file = build_xml_file
        attach_xml_to_invoice(xml_file)
        invoice.save!
      ensure
        cleanup_tempfiles(xml_file)
      end
    end

    def build_xml_file
      xml_file = Tempfile.new([invoice.number, ".xml"])
      xml_file.write(EInvoices::Invoices::Ubl::CreateService.call(invoice:).xml)
      xml_file.flush

      xml_file
    end

    # Upload before attaching: attach(io:) commits the attachment and uploads in after_commit,
    # so a worker stopped in between leaves an attachment without a file, which the re-run skips.
    def attach_xml_to_invoice(xml_file)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open(xml_file.path),
        filename: "#{invoice.number}.xml",
        content_type: "application/xml"
      )
      invoice.xml_file.attach(blob)
    end

    def cleanup_tempfiles(xml_file)
      xml_file&.unlink
    end

    def should_generate_xml?
      return false if invoice.product_catalog?
      return true if context == "admin"

      invoice.xml_file.blank? && e_invoicing_enabled?
    end

    def e_invoicing_enabled?
      invoice.billing_entity.eligible_for_einvoicing?
    end
  end
end
