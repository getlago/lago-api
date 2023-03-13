# frozen_string_literal: true

class InvoiceMailer < ApplicationMailer
  def finalized
    @invoice = params[:invoice]
    @organization = @invoice.organization
    @customer = @invoice.customer

    return if @organization.email.blank?
    return if @customer.email.blank?

    I18n.locale = @customer.preferred_document_locale

    mail(
      to: @customer.email,
      from: email_address_with_name(ENV['LAGO_FROM_EMAIL'], @organization.name),
      reply_to: email_address_with_name(@organization.email, @organization.name),
      subject: I18n.t(
        'email.invoice.finalized.subject',
        organization_name: @organization.name,
        invoice_number: @invoice.number,
      ),
    )
  end
end
