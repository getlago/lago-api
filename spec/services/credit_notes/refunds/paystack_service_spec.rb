# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::Refunds::PaystackService do
  subject(:service) { described_class.new(credit_note) }

  let(:organization) { create(:organization) }
  let(:code) { "paystack_live" }
  let(:payment_provider) { create(:paystack_provider, organization:, code:) }
  let(:customer) { create(:customer, organization:, payment_provider: "paystack", payment_provider_code: code) }
  let(:paystack_customer) { create(:paystack_customer, customer:, organization:, payment_provider:) }
  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 50_000,
      currency: "NGN",
      payment_status: "succeeded"
    )
  end

  let(:payment) do
    create(
      :payment,
      payment_provider:,
      payment_provider_customer: paystack_customer,
      customer:,
      organization:,
      payable: invoice,
      amount_cents: 50_000,
      amount_currency: "NGN",
      payable_payment_status: "succeeded",
      provider_payment_id: "4099260516",
      provider_payment_data: {"reference" => "lago-ref"}
    )
  end

  let(:credit_note) do
    create(
      :credit_note,
      organization:,
      customer:,
      invoice:,
      refund_amount_cents: 10_000,
      refund_amount_currency: "NGN",
      refund_status: :pending
    )
  end

  before do
    payment
    allow(SegmentTrackJob).to receive(:perform_later)
  end

  describe "#create" do
    let(:client) { instance_double(PaymentProviders::Paystack::Client) }

    before do
      allow(PaymentProviders::Paystack::Client).to receive(:new).and_return(client)
      allow(client).to receive(:create_refund).and_return(
        "data" => {
          "id" => 3_018_284,
          "amount" => 10_000,
          "currency" => "NGN",
          "status" => "pending"
        }
      )
    end

    it "creates a Paystack refund and keeps the credit note pending" do
      result = service.create

      expect(result).to be_success
      expect(result.refund).to have_attributes(
        credit_note:,
        payment:,
        payment_provider:,
        payment_provider_customer: paystack_customer,
        amount_cents: 10_000,
        amount_currency: "NGN",
        status: "pending",
        provider_refund_id: "3018284"
      )
      expect(result.credit_note).to be_pending
    end
  end

  describe "#update_status" do
    let(:refund) do
      create(
        :refund,
        credit_note:,
        payment:,
        organization:,
        payment_provider:,
        payment_provider_customer: paystack_customer,
        status: "pending",
        provider_refund_id: "3018284"
      )
    end

    before { refund }

    it "keeps needs-attention as pending" do
      result = described_class.new.update_status(provider_refund_id: "3018284", status: "needs-attention")

      expect(result).to be_success
      expect(result.refund.reload.status).to eq("needs-attention")
      expect(result.credit_note).to be_pending
    end

    it "marks processed refunds as succeeded" do
      result = described_class.new.update_status(provider_refund_id: "3018284", status: "processed")

      expect(result).to be_success
      expect(result.refund.reload.status).to eq("processed")
      expect(result.credit_note).to be_succeeded
      expect(result.credit_note.refunded_at).to be_present
    end

    it "delivers an error webhook for failed refunds" do
      result = described_class.new.update_status(provider_refund_id: "3018284", status: "failed")

      expect(result).not_to be_success
      expect(result.error.code).to eq("refund_failed")
      expect(SendWebhookJob).to have_been_enqueued.with(
        "credit_note.provider_refund_failure",
        credit_note,
        provider_customer_id: paystack_customer.provider_customer_id,
        provider_error: {
          message: "Payment refund failed",
          error_code: nil
        }
      )
    end

    it "treats reversed refunds as failed" do
      result = described_class.new.update_status(provider_refund_id: "3018284", status: "reversed")

      expect(result).not_to be_success
      expect(result.error.code).to eq("refund_failed")
      expect(result.refund.reload.status).to eq("reversed")
      expect(result.credit_note).to be_failed
    end
  end
end
