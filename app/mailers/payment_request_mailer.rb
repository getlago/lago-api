# frozen_string_literal: true

class PaymentRequestMailer < ApplicationMailer
  before_action :ensure_invoices_pdf

  def requested
    @payment_request = params[:payment_request]
    @organization = @payment_request.organization
    @show_lago_logo = !@organization.remove_branding_watermark_enabled?

    return if @payment_request.email.blank?
    return if @organization.email.blank?

    @customer = @payment_request.customer
    @invoices = @payment_request.invoices
    @payment_url = ::PaymentRequests::Payments::GeneratePaymentUrlService.call(payable: @payment_request).payment_url

    bcc_emails = @payment_request.dunning_campaign&.bcc_emails

    I18n.with_locale(@customer.preferred_document_locale) do
      mail(
        to: @payment_request.email,
        from: email_address_with_name(@organization.from_email_address, @organization.name),
        bcc: bcc_emails,
        reply_to: email_address_with_name(@organization.email, @organization.name),
        subject: I18n.t(
          "email.payment_request.requested.subject",
          organization_name: @organization.name
        )
      )
    end
  end

  private

  def ensure_invoices_pdf
    params[:payment_request].invoices.each do |invoice|
      Invoices::GeneratePdfService.new(invoice:).call
    end
  end
end
