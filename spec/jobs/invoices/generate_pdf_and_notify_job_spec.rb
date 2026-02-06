# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::GeneratePdfAndNotifyJob do
  subject { described_class.perform_now(invoice:, email:) }

  let(:invoice) { create(:invoice) }
  let(:email) { true }
  let(:notify) { email }

  it "enqueues GenerateDocumentsJob" do
    expect { subject }.to enqueue_job(Invoices::GenerateDocumentsJob)
      .with(invoice:, notify:)
  end

  context "with user_id and api_key_id" do
    it "passes user_id and api_key_id to GenerateDocumentsJob" do
      expect { described_class.perform_now(invoice:, email:, user_id: "user-123", api_key_id: "key-456") }
        .to enqueue_job(Invoices::GenerateDocumentsJob)
        .with(invoice:, notify:, user_id: "user-123", api_key_id: "key-456")
    end
  end
end
