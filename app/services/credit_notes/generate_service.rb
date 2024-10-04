# frozen_string_literal: true

module CreditNotes
  class GenerateService < BaseService
    def initialize(credit_note:, context: nil)
      @credit_note = credit_note
      @context = context

      super
    end

    def call
      return result.not_found_failure!(resource: 'credit_note') if credit_note.blank? || !credit_note.finalized?

      generate_pdf(credit_note) if should_generate_pdf?

      SendWebhookJob.perform_later('credit_note.generated', credit_note)

      result.credit_note = credit_note
      result
    end

    private

    attr_reader :credit_note, :context

    def generate_pdf(credit_note)
      I18n.locale = credit_note.customer.preferred_document_locale

      pdf_service = Utils::PdfGenerator.new(template: 'credit_note', context: credit_note)
      pdf_result = pdf_service.call

      credit_note.file.attach(
        io: pdf_result.io,
        filename: "#{credit_note.number}.pdf",
        content_type: 'application/pdf'
      )

      credit_note.save!
    end

    def should_generate_pdf?
      context == 'admin' || credit_note.file.blank?
    end
  end
end
