# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipts::GeneratePdfAndNotifyJob do
  let(:payment_receipt) { create(:payment_receipt) }
  let(:result) { BaseService::Result.new }
  let(:payment_receipt_mailer) { PaymentReceiptMailer.with(payment_receipt:) }

  before do
    allow(PaymentReceipts::GeneratePdfService).to receive(:call)
      .with(payment_receipt:, context: "api")
      .and_return(result)
    allow(PaymentReceiptMailer).to receive(:with)
      .with(payment_receipt:)
      .and_return(payment_receipt_mailer)
  end

  it "delegates to the Generate service" do
    described_class.perform_now(payment_receipt:, email: true)

    expect(PaymentReceipts::GeneratePdfService).to have_received(:call)
  end

  context "when email is true" do
    it "sends email" do
      expect { described_class.perform_now(payment_receipt:, email: true) }
        .to have_enqueued_mail(PaymentReceiptMailer, :created).with(params: {payment_receipt:}, args: [])
    end
  end

  context "when email is false" do
    it "does not send email" do
      expect { described_class.perform_now(payment_receipt:, email: false) }
        .not_to have_enqueued_mail(PaymentReceiptMailer, :created).with(params: {payment_receipt:}, args: [])
    end
  end
end
