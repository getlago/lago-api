# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::ExpirePendingService do
  subject(:result) { described_class.call(wallet_transaction:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:, organization:) }
  let(:invoice) { create(:invoice, :credit, organization:, customer:, status: :open, payment_status: :pending) }
  let(:created_at) { 2.hours.ago }

  let(:wallet_transaction) do
    create(:wallet_transaction, wallet:, organization:, invoice:, status: :pending, settled_at: nil,
      transaction_status: :purchased, invoice_requires_successful_payment: true, created_at:)
  end

  before do
    allow(PaymentIntents::ExpireService).to receive(:call!)
    allow(PaymentProviders::CancelPaymentService).to receive(:call!)
    allow(PaymentProviders::Stripe::Payments::RetrieveService).to receive(:call!)
  end

  shared_examples "fails the top-up" do
    it "closes its invoice and fails the top-up" do
      result

      expect(invoice.reload).to be_closed
      expect(wallet_transaction.reload).to be_failed
      expect(wallet_transaction.failed_at).to be_present
      expect(SendWebhookJob).to have_been_enqueued.with("wallet_transaction.updated", wallet_transaction)
    end

    it "expires the payment links of the invoice" do
      result

      expect(PaymentIntents::ExpireService).to have_received(:call!).with(invoice:)
    end
  end

  shared_examples "leaves the top-up pending" do
    it "leaves the top-up and its invoice as they are" do
      result

      expect(invoice.reload).to be_open
      expect(wallet_transaction.reload).to be_pending
      expect(SendWebhookJob).not_to have_been_enqueued.with("wallet_transaction.updated", wallet_transaction)
    end
  end

  context "when no payment was ever attempted" do
    it_behaves_like "fails the top-up"

    it "does not send an invoice webhook, since the invoice is invisible" do
      result

      expect(SendWebhookJob).not_to have_been_enqueued.with(a_string_starting_with("invoice."), anything)
    end
  end

  context "when the top-up was created less than an hour ago" do
    let(:created_at) { 50.minutes.ago }

    it_behaves_like "leaves the top-up pending"
  end

  context "when the top-up is paid by hand" do
    before { wallet_transaction.update!(payment_method_type: :manual) }

    context "when it was created 2 hours ago" do
      it_behaves_like "leaves the top-up pending"
    end

    context "when it was created more than 24 hours ago" do
      let(:created_at) { 25.hours.ago }

      it_behaves_like "fails the top-up"
    end
  end

  context "when its auto top-up rule is paid by hand" do
    before do
      wallet_transaction.update!(source: :threshold)
      create(:recurring_transaction_rule, wallet:, trigger: :threshold, threshold_credits: "5", payment_method_type: :manual)
    end

    it_behaves_like "leaves the top-up pending"

    context "when the top-up has its own payment method" do
      before do
        payment_method = create(:payment_method, customer:, organization:)
        wallet_transaction.update!(payment_method:)
      end

      it_behaves_like "fails the top-up"
    end
  end

  context "when its wallet is paid by hand" do
    before { wallet.update!(payment_method_type: :manual) }

    it_behaves_like "leaves the top-up pending"
  end

  context "when the top-up does not require a successful payment" do
    let(:invoice) { create(:invoice, :credit, organization:, customer:, status: :finalized, payment_status: :pending) }

    before { wallet_transaction.update!(invoice_requires_successful_payment: false) }

    it "leaves it to the customer, who manages the finalized invoice" do
      result

      expect(wallet_transaction.reload).to be_pending
      expect(invoice.reload).to be_finalized
    end
  end

  context "when the top-up is already settled" do
    before { wallet_transaction.update!(status: :settled, settled_at: Time.current) }

    it "does nothing" do
      result

      expect(wallet_transaction.reload).to be_settled
      expect(invoice.reload).to be_open
    end
  end

  context "when its invoice is still generating" do
    let(:invoice) { create(:invoice, :credit, organization:, customer:, status: :generating, payment_status: :pending) }

    it "waits for the invoice and its payment" do
      result

      expect(wallet_transaction.reload).to be_pending
      expect(invoice.reload).to be_generating
    end
  end

  context "when a merchant recorded part of the amount manually" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, status: "requires_action",
        payable_payment_status: :processing)
    end

    before do
      invoice.update!(total_amount_cents: 1_000, total_paid_amount_cents: 400)
      payment
    end

    it "keeps the invoice open so the rest can still be recorded" do
      result

      expect(invoice.reload).to be_open
      expect(wallet_transaction.reload).to be_pending
    end

    it "keeps every way to pay the rest" do
      result

      expect(PaymentProviders::Stripe::Payments::RetrieveService).not_to have_received(:call!)
      expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
      expect(PaymentIntents::ExpireService).not_to have_received(:call!)
    end
  end

  context "when the invoice was paid meanwhile" do
    let(:invoice) { create(:invoice, :credit, organization:, customer:, status: :open, payment_status: :succeeded) }

    it "leaves the top-up to the payment webhook" do
      result

      expect(wallet_transaction.reload).to be_pending
      expect(invoice.reload).to be_open
    end
  end

  context "when a payment link cannot be expired" do
    before do
      allow(PaymentIntents::ExpireService).to receive(:call!).and_raise(BaseService::ServiceFailure.new(BaseResult.new, code: "stripe_error", error_message: "boom"))
    end

    it "does not fail the top-up, which could still be paid through the link" do
      expect { result }.to raise_error(BaseService::ServiceFailure)

      expect(wallet_transaction.reload).to be_pending
      expect(invoice.reload).to be_open
    end
  end

  context "with a Stripe payment" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, status: "requires_action",
        payable_payment_status: :processing)
    end

    let(:live_status) { "requires_action" }
    let(:live_method) { "card" }
    let(:live_intent) do
      PaymentProviders::Stripe::Payments::RetrieveService::Result.new.tap do |intent|
        intent.status = live_status
        intent.payment_method_type = live_method
      end
    end

    before do
      payment
      allow(PaymentProviders::Stripe::Payments::RetrieveService).to receive(:call!).with(payment:).and_return(live_intent)
      allow(PaymentProviders::CancelPaymentService).to receive(:call!) do
        payment.update!(status: "canceled", payable_payment_status: :failed)
      end
    end

    context "when the end customer abandoned a 3DS challenge" do
      it_behaves_like "fails the top-up"

      it "cancels the payment before failing the top-up" do
        result

        expect(PaymentProviders::CancelPaymentService).to have_received(:call!).with(payment:)
      end
    end

    context "when the provider refuses the cancellation, since the intent moved on" do
      before { allow(PaymentProviders::CancelPaymentService).to receive(:call!).and_return(BaseResult.new) }

      it_behaves_like "leaves the top-up pending"
    end

    context "when the intent is waiting for a new payment method" do
      let(:live_status) { "requires_payment_method" }

      it_behaves_like "fails the top-up"
    end

    context "when the card charge is processing" do
      let(:live_status) { "processing" }

      it_behaves_like "leaves the top-up pending"

      it "does not cancel it" do
        result

        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
      end
    end

    context "when the provider says the customer has paid" do
      let(:live_status) { "succeeded" }

      it_behaves_like "leaves the top-up pending"
    end

    context "when the provider already cancelled the intent and its webhook never reached us" do
      let(:live_status) { "canceled" }

      it_behaves_like "fails the top-up"

      it "records the cancellation on the payment" do
        result

        expect(payment.reload).to have_attributes(status: "canceled", payable_payment_status: "failed")
        expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
      end
    end

    context "when it is a bank transfer waiting for the wire" do
      let(:payment) do
        create(:payment, :awaiting_bank_transfer, payable: invoice, customer:, organization:,
          payable_payment_status: :processing)
      end
      let(:live_method) { "customer_balance" }
      let(:created_at) { 6.days.ago }

      it_behaves_like "leaves the top-up pending"

      context "when the wire is still missing after 7 days" do
        let(:created_at) { 8.days.ago }

        it_behaves_like "fails the top-up"

        it "cancels the bank transfer before failing the top-up" do
          result

          expect(PaymentProviders::CancelPaymentService).to have_received(:call!).with(payment:)
        end
      end
    end

    context "when the provider rejects the stored key" do
      before do
        allow(PaymentProviders::Stripe::Payments::RetrieveService)
          .to receive(:call!).and_raise(::Stripe::AuthenticationError.new("invalid key"))
      end

      it_behaves_like "leaves the top-up pending"
    end
  end

  context "with a GoCardless direct debit pending" do
    before do
      create(:payment, :gocardless_payment, payable: invoice, customer:, organization:, payable_payment_status: :pending)
    end

    it_behaves_like "leaves the top-up pending"

    it "does not ask Stripe" do
      result

      expect(PaymentProviders::Stripe::Payments::RetrieveService).not_to have_received(:call!)
    end
  end

  context "with a payment that never reached the provider (no provider id)" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, provider_payment_id: nil,
        status: "pending", payable_payment_status: :pending)
    end
    let(:found_intents) { [] }

    before do
      payment
      allow(::Stripe::PaymentIntent).to receive(:search)
        .and_return(Stripe::SearchResultObject.construct_from(data: found_intents))
    end

    it_behaves_like "fails the top-up"

    it "fails the payment locally, since nothing can pay it" do
      result

      expect(payment.reload.payable_payment_status).to eq("failed")
      expect(PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end

    it "looks for an intent Stripe created despite the error" do
      result

      expect(::Stripe::PaymentIntent).to have_received(:search)
        .with(hash_including(query: "metadata['lago_payment_id']:'#{payment.id}'"), anything)
    end

    context "when Stripe created the intent anyway, and it is still processing" do
      let(:found_intents) { [{id: "pi_lost", object: "payment_intent"}] }

      before do
        allow(PaymentProviders::Stripe::Payments::RetrieveService).to receive(:call!).and_return(
          PaymentProviders::Stripe::Payments::RetrieveService::Result.new.tap do |intent|
            intent.status = "processing"
            intent.payment_method_type = "sepa_debit"
          end
        )
      end

      it_behaves_like "leaves the top-up pending"

      it "records the intent on the payment" do
        result

        expect(payment.reload.provider_payment_id).to eq("pi_lost")
      end
    end

    context "when Stripe cannot be searched" do
      before { allow(::Stripe::PaymentIntent).to receive(:search).and_raise(::Stripe::APIConnectionError.new("down")) }

      it_behaves_like "leaves the top-up pending"
    end

    context "with another provider" do
      let(:payment) do
        create(:payment, :gocardless_payment, payable: invoice, customer:, organization:, provider_payment_id: nil,
          status: "pending", payable_payment_status: :pending)
      end

      it_behaves_like "fails the top-up"
    end
  end

  context "when the webhook of our own cancel fails the top-up first" do
    before do
      allow(PaymentIntents::ExpireService).to receive(:call!) do
        WalletTransaction.find(wallet_transaction.id).mark_as_failed!
      end
    end

    it "closes the invoice without raising on the stale top-up" do
      expect { result }.not_to raise_error

      expect(invoice.reload).to be_closed
      expect(wallet_transaction.reload).to be_failed
    end
  end

  context "when a payment starts while the invoice is being closed" do
    before do
      allow(PaymentIntents::ExpireService).to receive(:call!) do
        create(:payment, payable: invoice, customer:, organization:, status: "processing", payable_payment_status: :processing)
      end
    end

    it_behaves_like "leaves the top-up pending"
  end
end
