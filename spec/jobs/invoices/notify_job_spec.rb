# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::NotifyJob do
  let(:invoice) { create(:invoice) }

  it "sends email" do
    expect { described_class.perform_now(invoice:) }
      .to have_enqueued_mail(InvoiceMailer, :created)
      .with(params: {invoice:}, args: [])
  end

  context "with user_id" do
    it "passes user_id to mailer" do
      expect { described_class.perform_now(invoice:, user_id: "user-123") }
        .to have_enqueued_mail(InvoiceMailer, :created)
        .with(params: {invoice:, user_id: "user-123"}, args: [])
    end
  end

  context "with api_key_id" do
    it "passes api_key_id to mailer" do
      expect { described_class.perform_now(invoice:, api_key_id: "key-456") }
        .to have_enqueued_mail(InvoiceMailer, :created)
        .with(params: {invoice:, api_key_id: "key-456"}, args: [])
    end
  end
end
