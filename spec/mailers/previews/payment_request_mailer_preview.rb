# frozen_string_literal: true

class PaymentRequestMailerPreview < BasePreviewMailer
  def requested
    payment_request = FactoryBot.create(:payment_request, amount_cents: 3000)
    first_invoice = FactoryBot.create(:invoice, total_amount_cents: 1000)
    second_invoice = FactoryBot.create(:invoice, total_amount_cents: 2000)

    first_invoice.file.attach(
      io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
      filename: "invoice.pdf",
      content_type: "application/pdf"
    )
    second_invoice.file.attach(
      io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
      filename: "invoice.pdf",
      content_type: "application/pdf"
    )

    FactoryBot.create(
      :payment_request_applied_invoice,
      invoice: first_invoice,
      payment_request:
    )
    FactoryBot.create(
      :payment_request_applied_invoice,
      invoice: second_invoice,
      payment_request:
    )

    PaymentRequestMailer.with(payment_request:).requested
  end
end
