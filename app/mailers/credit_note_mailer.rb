# frozen_string_literal: true

class CreditNoteMailer < ApplicationMailer
  before_action :ensure_pdf

  def created
    @credit_note = params[:credit_note]
    @customer = @credit_note.customer
    @billing_entity = @credit_note.billing_entity
    @show_lago_logo = !@billing_entity.organization.remove_branding_watermark_enabled?

    return if @billing_entity.email.blank?
    return if @customer.email.blank?

    if @pdfs_enabled
      @credit_note.file.open do |file|
        attachments["credit_note-#{@credit_note.number}.pdf"] = file.read
      end
    end

    I18n.with_locale(@customer.preferred_document_locale) do
      mail(
        to: @customer.email,
        from: email_address_with_name(@billing_entity.from_email_address, @billing_entity.name),
        reply_to: email_address_with_name(@billing_entity.email, @billing_entity.name),
        subject: I18n.t(
          "email.credit_note.created.subject",
          billing_entity_name: @billing_entity.name,
          credit_note_number: @credit_note.number
        )
      )
    end
  end

  private

  def ensure_pdf
    credit_note = params[:credit_note]

    CreditNotes::GenerateService.call(credit_note:)
  end
end
