# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequestMailer, type: :mailer do
  subject(:payment_request_mailer) { described_class }

  let(:first_invoice) { create(:invoice, total_amount_cents: 1000) }
  let(:second_invoice) { create(:invoice, total_amount_cents: 2000) }
  let(:payment_request) { create(:payment_request, invoices: [first_invoice, second_invoice]) }

  before do
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
  end

  describe "#requested" do
    specify do
      mailer = payment_request_mailer.with(payment_request:).requested

      expect(mailer.to).to eq([payment_request.email])
      expect(mailer.reply_to).to eq([payment_request.organization.email])
      expect(mailer.body.encoded).to include(first_invoice.number)
      expect(mailer.body.encoded).to include(second_invoice.number)
    end
  end
end
