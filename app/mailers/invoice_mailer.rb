# frozen_string_literal: true

class InvoiceMailer < ApplicationMailer
  before_action :ensure_pdf

  def finalized
    @invoice = params[:invoice]
    @organization = @invoice.organization
    @customer = @invoice.customer
    @show_lago_logo = !@organization.remove_branding_watermark_enabled?

    return if @organization.email.blank?
    return if @customer.email.blank?
    return if @invoice.fees_amount_cents.zero?

    I18n.locale = @customer.preferred_document_locale

    @invoice.file.open do |file|
      attachments["invoice-#{@invoice.number}.pdf"] = file.read
    end

    from_email = if @organization.from_email_enabled?
      @organization.email
    else
      ENV["LAGO_FROM_EMAIL"]
    end

    I18n.with_locale(@customer.preferred_document_locale) do
      mail(
        to: @customer.email,
        from: email_address_with_name(from_email, @organization.name),
        reply_to: email_address_with_name(@organization.email, @organization.name),
        subject: I18n.t(
          "email.invoice.finalized.subject",
          organization_name: @organization.name,
          invoice_number: @invoice.number
        )
      )
    end
  end

  private

  def ensure_pdf
    invoice = params[:invoice]

    Invoices::GeneratePdfService.new(invoice:).call
  end
end
