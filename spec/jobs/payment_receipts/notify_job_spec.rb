# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipts::NotifyJob do
  let(:payment_receipt) { create(:payment_receipt) }

  it "sends the email" do
    expect { described_class.perform_now(payment_receipt:) }
      .to have_enqueued_mail(PaymentReceiptMailer, :created)
      .with(params: {payment_receipt:}, args: [])
  end

  context "with user_id" do
    it "passes user_id to mailer" do
      expect { described_class.perform_now(payment_receipt:, user_id: "user-123") }
        .to have_enqueued_mail(PaymentReceiptMailer, :created)
        .with(params: {payment_receipt:, user_id: "user-123"}, args: [])
    end
  end

  context "with api_key_id" do
    it "passes api_key_id to mailer" do
      expect { described_class.perform_now(payment_receipt:, api_key_id: "key-456") }
        .to have_enqueued_mail(PaymentReceiptMailer, :created)
        .with(params: {payment_receipt:, api_key_id: "key-456"}, args: [])
    end
  end
end
