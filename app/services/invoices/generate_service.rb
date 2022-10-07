# frozen_string_literal: true

module Invoices
  class GenerateService < BaseService
    def generate_from_api(invoice)
      generate_pdf(invoice)

      SendWebhookJob.perform_later('invoice.generated', invoice)
    end

    def generate(invoice_id:)
      invoice = Invoice.find_by(id: invoice_id)
      return result.not_found_failure!(resource: 'invoice') if invoice.blank?

      generate_pdf(invoice) if invoice.file.blank?

      result.invoice = invoice

      result
    end

    private

    def generate_pdf(invoice)
      pdf_service = Utils::PdfGenerator.new(template: 'invoice', context: invoice)
      pdf_result = pdf_service.call

      invoice.file.attach(
        io: pdf_result.io,
        filename: "#{invoice.number}.pdf",
        content_type: 'application/pdf',
      )

      invoice.save!
    end
  end
end
