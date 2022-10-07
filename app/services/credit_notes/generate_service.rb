# frozen_string_literal: true

module CreditNotes
  class GenerateService < BaseService
    def call_from_api(credit_note:)
      generate_pdf(credit_note)

      SendWebhookJob.perform_later('credit_note.generated', credit_note)
    end

    def call(credit_note_id:)
      credit_note = CreditNote.find_by(id: credit_note_id)
      return result.not_found_failure!(resource: 'credit_note') if credit_note.blank?

      generate_pdf(credit_note) if credit_note.file.blank?

      result.credit_note = credit_note
      result
    end

    private

    def generate_pdf(credit_note)
      pdf_service = Utils::PdfGenerator.new(template: 'credit_note', context: credit_note)
      pdf_result = pdf_service.call

      credit_note.file.attach(
        io: pdf_result.io,
        filename: "#{credit_note.number}.pdf",
        content_type: 'application/pdf',
      )

      credit_note.save!
    end
  end
end
