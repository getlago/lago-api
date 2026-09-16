# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CancelAbandonedService do
  subject(:result) { described_class.call(payment:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:, status: :finalized, payment_status: :pending, ready_for_payment_processing: false) }

  let(:payment) do
    create(:payment, payable: invoice, customer:, organization:, status: "requires_action",
      payable_payment_status: :processing, updated_at: 2.days.ago,
      provider_payment_data: {"type" => "redirect_to_url"})
  end

  let(:live_status) { "requires_action" }
  let(:live_method) { "card" }

  let(:live_intent) do
    ::PaymentProviders::Stripe::Payments::RetrieveService::Result.new.tap do |intent|
      intent.status = live_status
      intent.payment_method_type = live_method
    end
  end

  before do
    allow(::PaymentProviders::Stripe::Payments::RetrieveService).to receive(:call!).and_return(live_intent)

    allow(::PaymentProviders::CancelPaymentService).to receive(:call!) do
      payment.update!(status: "canceled", payable_payment_status: :failed)
    end
  end

  it "cancels the payment at the provider" do
    result

    expect(::PaymentProviders::CancelPaymentService).to have_received(:call!).with(payment:)
  end

  it "makes the invoice payable again" do
    expect { result }.to change { invoice.reload.ready_for_payment_processing }.from(false).to(true)
  end

  it "leaves the invoice payment status to the provider webhook" do
    expect { result }.not_to change { invoice.reload.payment_status }
  end

  it "does not duplicate the event that webhook will carry" do
    expect { result }.not_to have_enqueued_job(SendWebhookJob)
  end

  context "when the customer completes the payment while we are cancelling" do
    before do
      allow(::PaymentProviders::CancelPaymentService).to receive(:call!) do
        # The provider refuses an intent that has just succeeded, and its webhook lands the real
        # status on both records before this service reloads them.
        payment.update!(payable_payment_status: :succeeded)
        invoice.update!(payment_status: :succeeded)
      end
    end

    it "leaves the invoice locked rather than reopening a paid one" do
      expect { result }.not_to change { invoice.reload.ready_for_payment_processing }
    end
  end

  context "when the provider refuses the cancellation" do
    before do
      allow(::PaymentProviders::CancelPaymentService).to receive(:call!).and_return(BaseResult.new)
    end

    it "leaves the invoice locked, since the intent moved on without us" do
      expect { result }.not_to change { invoice.reload.ready_for_payment_processing }
    end
  end

  context "when the payment is a bank transfer waiting on the wire" do
    let(:payment) do
      create(:payment, :awaiting_bank_transfer, payable: invoice, customer:, organization:,
        payable_payment_status: :processing, updated_at: 2.days.ago)
    end

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the customer was redirected minutes ago" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, status: "requires_action",
        payable_payment_status: :processing, updated_at: 5.minutes.ago,
        provider_payment_data: {"type" => "redirect_to_url"})
    end

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the row is old but the redirect is fresh" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, status: "requires_action",
        payable_payment_status: :processing, created_at: 6.months.ago, updated_at: 1.hour.ago,
        provider_payment_data: {"type" => "redirect_to_url"})
    end

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the payment already settled" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, status: "requires_action",
        payable_payment_status: :succeeded, updated_at: 2.days.ago,
        provider_payment_data: {"type" => "redirect_to_url"})
    end

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the payment is awaiting capture" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, status: "requires_capture",
        payable_payment_status: :processing, updated_at: 2.days.ago)
    end

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the provider has already cancelled the intent" do
    let(:live_status) { "canceled" }

    it "does not try to cancel what is already gone" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end

    it "brings the payment in line with the provider" do
      expect { result }.to change { payment.reload.payable_payment_status }
        .from("processing").to("failed")
    end

    it "releases the invoice, which the missing webhook never did" do
      expect { result }.to change { invoice.reload.ready_for_payment_processing }.from(false).to(true)
    end

    it "marks the invoice failed, the other half of what that webhook would have done" do
      expect { result }.to change { invoice.reload.payment_status }.from("pending").to("failed")
    end

    it "tells the merchant, since nothing else will" do
      expect { result }.to have_enqueued_job(SendWebhookJob)
        .with("invoice.payment_status_updated", invoice)
    end
  end

  context "when the provider is waiting for a new payment method" do
    let(:live_status) { "requires_payment_method" }

    it "releases the invoice too, since the intent is over either way" do
      expect { result }.to change { invoice.reload.ready_for_payment_processing }.from(false).to(true)
    end
  end

  context "when the provider says the payment is not a card" do
    let(:live_method) { "crypto" }

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the provider says the customer has paid" do
    let(:live_status) { "succeeded" }

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end

    it "leaves the invoice locked, since only the webhook can settle a payment" do
      expect { result }.not_to change { invoice.reload.ready_for_payment_processing }
    end
  end

  context "when the cancellation itself fails" do
    before do
      allow(::PaymentProviders::CancelPaymentService)
        .to receive(:call!).and_raise(Stripe::InvalidRequestError.new("nope", nil))
    end

    it "surfaces it instead of logging it as an unreadable intent" do
      expect { result }.to raise_error(Stripe::InvalidRequestError)
    end
  end

  context "when the provider rejects the stored key" do
    before do
      allow(::PaymentProviders::Stripe::Payments::RetrieveService)
        .to receive(:call!).and_raise(Stripe::AuthenticationError.new("bad key"))
    end

    it "does nothing, since the answer will be the same an hour from now" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end

    it "does not fail the job" do
      expect { result }.not_to raise_error
    end
  end

  context "when the provider is rate limiting us" do
    before do
      allow(::PaymentProviders::Stripe::Payments::RetrieveService)
        .to receive(:call!).and_raise(Stripe::RateLimitError.new("slow down"))
    end

    it "lets it through so the job retries instead of skipping the payment" do
      expect { result }.to raise_error(Stripe::RateLimitError)
    end
  end

  context "when the payment gates a subscription activation" do
    before { allow(payment).to receive(:gated_subscription_activation?).and_return(true) }

    it "leaves it to the activation flow, which has its own window" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the payment predates the provider data column" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, status: "requires_action",
        payable_payment_status: :processing, updated_at: 2.days.ago, provider_payment_data: nil)
    end

    it "skips it instead of raising, since the column is nullable" do
      expect { result }.not_to raise_error
    end

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the redirect went stale before the recovery window" do
    let(:payment) do
      create(:payment, payable: invoice, customer:, organization:, status: "requires_action",
        payable_payment_status: :processing, updated_at: 6.months.ago,
        provider_payment_data: {"type" => "redirect_to_url"})
    end

    it "leaves the older backlog to a deliberate decision" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the invoice was already paid" do
    let(:invoice) { create(:invoice, organization:, customer:, status: :finalized, payment_status: :succeeded, ready_for_payment_processing: false) }

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the invoice was voided" do
    let(:invoice) { create(:invoice, organization:, customer:, status: :voided, payment_status: :pending, ready_for_payment_processing: false) }

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end

  context "when the payable is not an invoice" do
    let(:payment_request) { create(:payment_request, organization:, customer:) }
    let(:payment) do
      create(:payment, payable: payment_request, customer:, organization:, status: "requires_action",
        payable_payment_status: :processing, provider_payment_data: {"type" => "redirect_to_url"})
    end

    it "does not cancel anything" do
      result

      expect(::PaymentProviders::CancelPaymentService).not_to have_received(:call!)
    end
  end
end
