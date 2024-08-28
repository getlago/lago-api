# frozen_string_literal: true

class PaymentRequestMailer < ApplicationMailer
  before_action :ensure_invoices_pdf

  def requested
    @payment_request = params[:payment_request]
    @organization = @payment_request.organization
    @customer = @payment_request.customer
    @invoices = @payment_request.invoices

    I18n.with_locale(@customer.preferred_document_locale) do
      mail(
        to: @payment_request.email,
        from: email_address_with_name(ENV["LAGO_FROM_EMAIL"], @organization.name),
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
