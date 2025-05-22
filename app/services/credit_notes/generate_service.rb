# frozen_string_literal: true

module CreditNotes
  class GenerateService < BaseService
    def initialize(credit_note:, context: nil)
      @credit_note = credit_note
      @context = context

      super
    end

    def call
      return result.not_found_failure!(resource: "credit_note") if credit_note.blank? || !credit_note.finalized?

      if should_generate_pdf?
        generate_pdf(credit_note)
        SendWebhookJob.perform_later("credit_note.generated", credit_note)
        Utils::ActivityLog.produce(credit_note, "credit_note.generated")
      end

      result.credit_note = credit_note
      result
    end

    private

    attr_reader :credit_note, :context

    def generate_pdf(credit_note)
      I18n.locale = credit_note.customer.preferred_document_locale

      pdf_result = Utils::PdfGenerator.call(template:, context: credit_note)

      credit_note.file.attach(
        io: pdf_result.io,
        filename: "#{credit_note.number}.pdf",
        content_type: "application/pdf"
      )

      credit_note.save!
    end

    def should_generate_pdf?
      return false if ActiveModel::Type::Boolean.new.cast(ENV["LAGO_DISABLE_PDF_GENERATION"])

      context == "admin" || credit_note.file.blank?
    end

    def template
      return "credit_notes/self_billed" if credit_note.invoice.self_billed?

      "credit_notes/credit_note"
    end
  end
end
