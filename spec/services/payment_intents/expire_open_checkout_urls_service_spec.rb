# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentIntents::ExpireOpenCheckoutUrlsService do
  subject(:result) { described_class.call(invoice:) }

  let(:invoice) { create(:invoice) }
  let(:provider_service) do
    instance_double(Invoices::Payments::StripeService, expire_checkout_session: nil)
  end

  before do
    allow(Invoices::Payments::PaymentProviders::Factory)
      .to receive(:new_instance).with(invoice:).and_return(provider_service)
  end

  context "when the invoice is blank" do
    let(:invoice) { nil }

    it "returns a success result without contacting the provider" do
      expect(result).to be_success
      expect(Invoices::Payments::PaymentProviders::Factory).not_to have_received(:new_instance)
    end
  end

  context "when there are no open intents with a provider_session_id" do
    before { create(:payment_intent, invoice:, provider_session_id: nil) }

    it "does not contact the provider" do
      result
      expect(Invoices::Payments::PaymentProviders::Factory).not_to have_received(:new_instance)
    end
  end

  context "with an open intent that has a provider_session_id" do
    let!(:payment_intent) do
      create(:payment_intent, invoice:, provider_session_id: "cs_test_open")
    end

    it "expires the session on the provider" do
      result
      expect(provider_service).to have_received(:expire_checkout_session).with(payment_intent)
    end

    it "marks the intent expired locally" do
      expect { result }.to change { payment_intent.reload.status }.from("active").to("expired")
    end
  end

  context "when an intent's status is already expired" do
    before { create(:payment_intent, :expired, invoice:, provider_session_id: "cs_old") }

    it "skips it" do
      result
      expect(provider_service).not_to have_received(:expire_checkout_session)
    end
  end
end
