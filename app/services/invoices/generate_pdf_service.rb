# frozen_string_literal: true

module Invoices
  class GeneratePdfService < BaseService
    def initialize(invoice:, context: nil)
      @invoice = invoice
      @context = context

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") if invoice.blank?
      return result.not_allowed_failure!(code: "is_draft") if invoice.draft?

      if should_generate_pdf?
        generate_pdf
        SendWebhookJob.perform_later("invoice.generated", invoice)
        Utils::ActivityLog.produce(invoice, "invoice.generated")
      end

      result.invoice = invoice
      result
    end

    def render_html
      Utils::PdfGenerator.new(template:, context: invoice).render_html
    end

    private

    attr_reader :invoice, :context

    def generate_pdf
      I18n.with_locale(invoice.customer.preferred_document_locale) do
        pdf_service = Utils::PdfGenerator.new(template:, context: invoice)
        pdf_result = pdf_service.call

        # TODO add tests for this class when attributes for billing_entity are created!
        pdf_file = Tempfile.new([invoice.number, ".pdf"])
        pdf_file.binmode
        pdf_file.write(pdf_result.io.read)
        pdf_file.flush

        if invoice.billing_entity&.country == "FR"
          xml_file = Tempfile.new([invoice.number, ".xml"])
          xml_file.write(EInvoices::FacturX::CreateService.call(invoice:))
          xml_file.flush

          Invoices::PdfAttachmentService.call(file: pdf_file, attachment: xml_file)
        end

        invoice.file.attach(
          io: File.open(pdf_file.path),
          filename: "#{invoice.number}.pdf",
          content_type: "application/pdf"
        )

        invoice.save!
      ensure
        pdf_file&.unlink
        xml_file&.unlink
      end
    end

    def template
      if invoice.self_billed?
        "invoices/v#{invoice.version_number}/self_billed"

      elsif invoice.one_off?
        return "invoices/v3/one_off" if invoice.version_number < 4

        "invoices/v#{invoice.version_number}/one_off"
      elsif charge?
        return "invoices/v3/charge" if invoice.version_number < 4

        "invoices/v#{invoice.version_number}/charge"
      else
        "invoices/v#{invoice.version_number}"
      end
    end

    def should_generate_pdf?
      return false if ActiveModel::Type::Boolean.new.cast(ENV["LAGO_DISABLE_PDF_GENERATION"])

      context == "admin" || invoice.file.blank?
    end

    def charge?
      invoice.fees.present? && invoice.fees.all?(&:pay_in_advance?)
    end
  end
end
