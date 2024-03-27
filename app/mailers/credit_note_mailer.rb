# frozen_string_literal: true

class CreditNoteMailer < ApplicationMailer
  before_action :ensure_pdf

  def created
    @credit_note = params[:credit_note]
    @organization = @credit_note.organization
    @customer = @credit_note.customer

    return if @organization.email.blank?
    return if @customer.email.blank?

    @credit_note.file.open do |file|
      attachments["credit_note.pdf"] = file.read
    end

    I18n.with_locale(@customer.preferred_document_locale) do
      mail(
        to: @customer.email,
        from: email_address_with_name(ENV["LAGO_FROM_EMAIL"], @organization.name),
        reply_to: email_address_with_name(@organization.email, @organization.name),
        subject: I18n.t(
          "email.credit_note.created.subject",
          organization_name: @organization.name,
          credit_note_number: @credit_note.number
        )
      )
    end
  end

  private

  def ensure_pdf
    credit_note = params[:credit_note]

    CreditNotes::GenerateService.new(credit_note:).call
  end
end
