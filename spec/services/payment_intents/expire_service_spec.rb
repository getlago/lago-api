# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentIntents::ExpireService do
  describe ".call" do
    subject(:result) { described_class.call(invoice:) }

    let(:factory) { Invoices::Payments::PaymentProviders::Factory }

    context "when invoice does not exist" do
      let(:invoice) { nil }

      it "fails with invoice not found error" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("invoice_not_found")
      end
    end

    context "when invoice exists" do
      let(:invoice) { create(:invoice) }

      before { allow(factory).to receive(:new_instance) }

      context "when there is no active payment intent" do
        it "returns without calling the provider" do
          expect(result).to be_success
          expect(result.checkout_paid).to be_nil
          expect(factory).not_to have_received(:new_instance)
        end
      end

      context "when the active payment intent has no provider session id" do
        let!(:payment_intent) { create(:payment_intent, invoice:, provider_payment_url_id: nil) }

        it "returns without calling the provider and keeps it active" do
          expect(result).to be_success
          expect(payment_intent.reload.status).to eq("active")
          expect(factory).not_to have_received(:new_instance)
        end
      end

      context "when the active payment intent has a provider session id" do
        let!(:payment_intent) { create(:payment_intent, invoice:, provider_payment_url_id: "cs_test_123") }
        let(:provider_service) { instance_double(Invoices::Payments::StripeService) }

        before do
          allow(factory).to receive(:new_instance).with(invoice:).and_return(provider_service)
          allow(provider_service).to receive(:expire_payment_url).with(payment_intent)
            .and_return(BaseService::Result.new.tap { |r| r.checkout_paid = checkout_paid })
        end

        context "when the checkout has not been paid" do
          let(:checkout_paid) { false }

          it "expires the payment intent (status and expires_at)" do
            expect(result).to be_success
            expect(result.checkout_paid).to be(false)
            expect(payment_intent.reload.status).to eq("expired")
            expect(payment_intent.expires_at).to be <= Time.current
            expect(PaymentIntent.non_expired).not_to include(payment_intent)
          end
        end

        context "when the customer is completing the checkout" do
          let(:checkout_paid) { true }

          it "keeps the payment intent active and flags checkout_paid" do
            expect(result).to be_success
            expect(result.checkout_paid).to be(true)
            expect(payment_intent.reload.status).to eq("active")
          end
        end
      end
    end
  end
end
