# frozen_string_literal: true

module Invoices
  class GeneratePdfService < BaseService
    def initialize(invoice:, context: nil)
      @invoice = invoice
      @context = context

      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.blank?
      return result.not_allowed_failure!(code: 'is_draft') if invoice.draft?

      generate_pdf if invoice.file.blank?

      SendWebhookJob.perform_later('invoice.generated', invoice) if should_send_webhook?

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :context

    def generate_pdf
      I18n.with_locale(invoice.customer.preferred_document_locale) do
        pdf_service = Utils::PdfGenerator.new(template:, context: invoice)
        pdf_result = pdf_service.call

        invoice.file.attach(
          io: pdf_result.io,
          filename: "#{invoice.number}.pdf",
          content_type: 'application/pdf',
        )

        invoice.save!
      end
    end

    def template
      if invoice.one_off?
        'invoices/one_off'
      else
        "invoices/v#{invoice.version_number}"
      end
    end

    def should_send_webhook?
      context == 'api'
    end
  end
end
