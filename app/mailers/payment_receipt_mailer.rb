# frozen_string_literal: true

class PaymentReceiptMailer < ApplicationMailer
  before_action :ensure_payment_receipt_pdf

  def created
    @payment_receipt = params[:payment_receipt]
    @billing_entity = @payment_receipt.billing_entity
    @customer = @payment_receipt.payment.payable.customer
    @show_lago_logo = !@billing_entity.organization.remove_branding_watermark_enabled?
    @total_due_amount = @payment_receipt.payment.payable.is_a?(Invoice) ?
      @payment_receipt.payment.payable.total_due_amount :
      @payment_receipt.payment.payable.amount - @payment_receipt.payment.amount

    return if @billing_entity.email.blank?
    return if @customer.email.blank?

    @invoices = if @payment_receipt.payment.payable.is_a?(Invoice)
      [@payment_receipt.payment.payable]
    else
      @payment_receipt.payment.payable.invoices
    end

    I18n.locale = @customer.preferred_document_locale

    if @pdfs_enabled
      @payment_receipt.file.open { |file| attachments["receipt-#{@payment_receipt.number}.pdf"] = file.read }

      @invoices.each do |invoice|
        invoice.file.open { |file| attachments["invoice-#{invoice.number}.pdf"] = file.read }
      end
    end

    I18n.with_locale(@customer.preferred_document_locale) do
      mail(
        to: @customer.email,
        from: email_address_with_name(@billing_entity.from_email_address, @billing_entity.name),
        reply_to: email_address_with_name(@billing_entity.email, @billing_entity.name),
        subject: I18n.t(
          "email.payment_receipt.created.subject",
          billing_entity_name: @billing_entity.name,
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
