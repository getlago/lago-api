# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CancelAbandonedService do
  subject(:cancel_service) { described_class.new(payment:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, ready_for_payment_processing: false) }

  let(:payment) do
    create(
      :payment,
      :requires_action,
      payable: invoice,
      customer:,
      organization:,
      payable_payment_status: "processing",
      created_at: 25.hours.ago
    )
  end

  before do
    allow(PaymentProviders::Stripe::Payments::CheckAbandonedAuthenticationService)
      .to receive(:call!)
      .and_return(PaymentProviders::Stripe::Payments::CheckAbandonedAuthenticationService::Result.new.tap { it.abandoned = true })

    allow(PaymentProviders::CancelPaymentService).to receive(:call!) do |payment:|
      payment.update!(status: "canceled", payable_payment_status: "failed")
      PaymentProviders::CancelPaymentService::Result.new
    end
  end

  describe "#call" do
    it "cancels the payment at the provider" do
      cancel_service.call

      expect(PaymentProviders::CancelPaymentService).to have_received(:call!).with(payment:)
    end

    it "makes the invoice payable again" do
      expect { cancel_service.call }
        .to change { invoice.reload.ready_for_payment_processing }.from(false).to(true)
    end

    it "leaves the invoice payment status untouched" do
      expect { cancel_service.call }.not_to change { invoice.reload.payment_status }
    end

    it "returns the payment" do
      expect(cancel_service.call.payment).to eq(payment)
    end

    context "when the challenge is still the current state at the provider" do
      before do
        allow(PaymentProviders::CancelPaymentService).to receive(:call!)
          .and_return(PaymentProviders::CancelPaymentService::Result.new)
      end

      it "does not unlock the invoice" do
        expect { cancel_service.call }.not_to change { invoice.reload.ready_for_payment_processing }
      end
    end

    context "when the payment is waiting on an incoming bank transfer" do
      before { payment.update!(provider_payment_data: {type: "display_bank_transfer_instructions"}) }

      it "leaves the collection in transit" do
        cancel_service.call

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
        expect(invoice.reload.ready_for_payment_processing).to be(false)
      end
    end

    context "when the payment is waiting on ACH microdeposit verification" do
      before { payment.update!(provider_payment_data: {type: "verify_with_microdeposits"}) }

      it "does nothing" do
        cancel_service.call

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
      end
    end

    context "when the provider says the intent is not an abandoned challenge" do
      before do
        allow(PaymentProviders::Stripe::Payments::CheckAbandonedAuthenticationService)
          .to receive(:call!)
          .and_return(PaymentProviders::Stripe::Payments::CheckAbandonedAuthenticationService::Result.new.tap { it.abandoned = false })
      end

      it "does not cancel it" do
        cancel_service.call

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
        expect(invoice.reload.ready_for_payment_processing).to be(false)
      end
    end

    context "when the payment is no longer awaiting authentication" do
      before { payment.update!(status: "processing") }

      it "does nothing" do
        cancel_service.call

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
        expect(invoice.reload.ready_for_payment_processing).to be(false)
      end
    end

    context "when the invoice was paid in the meantime" do
      before { invoice.update!(payment_status: "succeeded") }

      it "does nothing" do
        cancel_service.call

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
      end
    end

    context "when the invoice was voided" do
      before { invoice.update!(status: "voided") }

      it "does nothing" do
        cancel_service.call

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
      end
    end

    context "when the payment gates a subscription activation" do
      before { allow(payment).to receive(:gated_subscription_activation?).and_return(true) }

      it "leaves it to the subscription activation flow" do
        cancel_service.call

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
      end
    end

    context "when the payable is not an invoice" do
      let(:invoice) { create(:payment_request, customer:, organization:) }

      it "does nothing" do
        cancel_service.call

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
      end
    end
  end
end
