# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentIntents::ReconcileOpenCheckoutUrlsService do
  subject(:result) { described_class.call(invoice:) }

  let(:invoice) { create(:invoice) }
  let(:provider_service) do
    instance_double(
      Invoices::Payments::StripeService,
      checkout_session_already_completed?: completed,
      expire_checkout_session: nil
    )
  end
  let(:completed) { false }

  before do
    allow(Invoices::Payments::PaymentProviders::Factory)
      .to receive(:new_instance).with(invoice:).and_return(provider_service)
  end

  context "when the invoice is blank" do
    let(:invoice) { nil }

    it "returns a success result with already_paid_via_checkout=false" do
      expect(result).to be_success
      expect(result.already_paid_via_checkout).to be false
    end

    it "does not contact the provider" do
      result
      expect(Invoices::Payments::PaymentProviders::Factory).not_to have_received(:new_instance)
    end
  end

  context "when there are no open intents with a provider_session_id" do
    before { create(:payment_intent, invoice:, provider_session_id: nil) }

    it "returns already_paid_via_checkout=false without contacting the provider" do
      expect(result.already_paid_via_checkout).to be false
      expect(Invoices::Payments::PaymentProviders::Factory).not_to have_received(:new_instance)
    end
  end

  context "when the open intent has not been paid via the URL" do
    let!(:payment_intent) do
      create(:payment_intent, invoice:, provider_session_id: "cs_test_open")
    end

    it "expires the intent locally" do
      expect { result }.to change { payment_intent.reload.status }.from("active").to("expired")
    end

    it "expires the session on the provider" do
      result
      expect(provider_service).to have_received(:expire_checkout_session).with(payment_intent)
    end

    it "returns already_paid_via_checkout=false" do
      expect(result.already_paid_via_checkout).to be false
    end
  end

  context "when the URL was already paid on the provider side" do
    let(:completed) { true }
    let!(:payment_intent) do
      create(:payment_intent, invoice:, provider_session_id: "cs_test_paid")
    end

    it "returns already_paid_via_checkout=true" do
      expect(result.already_paid_via_checkout).to be true
    end

    it "does not expire the intent locally" do
      expect { result }.not_to change { payment_intent.reload.status }
    end

    it "does not call expire_checkout_session" do
      result
      expect(provider_service).not_to have_received(:expire_checkout_session)
    end
  end

  context "when expire raises a transient provider error" do
    let!(:payment_intent) do
      create(:payment_intent, invoice:, provider_session_id: "cs_test_open")
    end

    before do
      allow(provider_service).to receive(:expire_checkout_session)
        .and_raise(Invoices::Payments::ConnectionError.new(StandardError.new("boom")))
    end

    it "does not block the auto-charge" do
      expect { result }.not_to raise_error
    end

    it "does not mark the intent expired locally (so retry can re-attempt)" do
      expect { result }.not_to change { payment_intent.reload.status }
    end

    it "returns already_paid_via_checkout=false" do
      expect(result.already_paid_via_checkout).to be false
    end
  end

  context "when an intent's status is already expired" do
    before { create(:payment_intent, :expired, invoice:, provider_session_id: "cs_old") }

    it "does not reconsider it" do
      result
      expect(provider_service).not_to have_received(:checkout_session_already_completed?)
    end
  end
end
