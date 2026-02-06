# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReceipts::GeneratePdfAndNotifyJob do
  subject { described_class.perform_now(payment_receipt:, email:) }

  let(:payment_receipt) { create(:payment_receipt) }
  let(:email) { true }
  let(:notify) { email }

  it "enqueues GenerateDocumentsJob" do
    expect { subject }.to enqueue_job(PaymentReceipts::GenerateDocumentsJob)
      .with(payment_receipt:, notify:)
  end

  context "with user_id and api_key_id" do
    it "passes user_id and api_key_id to GenerateDocumentsJob" do
      expect { described_class.perform_now(payment_receipt:, email:, user_id: "user-123", api_key_id: "key-456") }
        .to enqueue_job(PaymentReceipts::GenerateDocumentsJob)
        .with(payment_receipt:, notify:, user_id: "user-123", api_key_id: "key-456")
    end
  end
end
