# frozen_string_literal: true

class PaymentReceiptMailer < ApplicationMailer
  before_action :ensure_payment_receipt_pdf

  def created
    @payment_receipt = params[:payment_receipt]
    @organization = @payment_receipt.organization
    @customer = @payment_receipt.payment.payable.customer
    @show_lago_logo = !@organization.remove_branding_watermark_enabled?

    return if @organization.email.blank?
    return if @customer.email.blank?

    @invoices = if @payment_receipt.payment.payable.is_a?(Invoice)
      [@payment_receipt.payment.payable]
    else
      @payment_receipt.payment.payable.invoices
    end

    I18n.locale = @customer.preferred_document_locale

    @payment_receipt.file.open { |file| attachments["receipt-#{@payment_receipt.number}.pdf"] = file.read }

    @invoices.each do |invoice|
      invoice.file.open { |file| attachments["invoice-#{invoice.number}.pdf"] = file.read }
    end

    I18n.with_locale(@customer.preferred_document_locale) do
      mail(
        to: @customer.email,
        from: email_address_with_name(@organization.from_email_address, @organization.name),
        reply_to: email_address_with_name(@organization.email, @organization.name),
        subject: I18n.t(
          "email.payment_receipt.created.subject",
          organization_name: @organization.name,
          payment_receipt_number: @payment_receipt.number
        )
      )
    end
  end

  private

  def ensure_payment_receipt_pdf
    payment_receipt = params[:payment_receipt]

    PaymentReceipts::GeneratePdfService.new(payment_receipt:).call
  end
end
