# frozen_string_literal: true

module PaymentReceipts
  class GeneratePdfService < BaseService
    def initialize(payment_receipt:, context: nil)
      @payment_receipt = payment_receipt
      @context = context

      super
    end

    def call
      return result.not_found_failure!(resource: "payment_receipt") if payment_receipt.blank?

      if should_generate_pdf?
        generate_pdf
        SendWebhookJob.perform_later("payment_receipt.generated", payment_receipt)
        Utils::ActivityLog.produce(payment_receipt, "payment_receipt.generated")
      end

      result.payment_receipt = payment_receipt
      result
    end

    def render_html
      Utils::PdfGenerator.new(template:, context: payment_receipt).render_html
    end

    private

    attr_reader :payment_receipt, :context

    def generate_pdf
      I18n.with_locale(payment_receipt.payment.customer.preferred_document_locale) do
        pdf_service = Utils::PdfGenerator.new(template:, context: payment_receipt)
        pdf_result = pdf_service.call

        payment_receipt.file.attach(
          io: pdf_result.io,
          filename: "#{payment_receipt.number}.pdf",
          content_type: "application/pdf"
        )

        payment_receipt.save!
      end
    end

    def template
      "payment_receipts/v1"
    end

    def should_generate_pdf?
      return false if ActiveModel::Type::Boolean.new.cast(ENV["LAGO_DISABLE_PDF_GENERATION"])

      context == "admin" || payment_receipt.file.blank?
    end
  end
end
