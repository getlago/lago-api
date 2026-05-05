# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Paystack::HandleEventService do
  subject(:result) { described_class.call(organization:, payment_provider:, event_json:) }

  let(:organization) { create(:organization) }
  let(:code) { "paystack_live" }
  let(:payment_provider) { create(:paystack_provider, organization:, code:) }
  let(:client) { instance_double(PaymentProviders::Paystack::Client) }
  let(:event_json) { {"event" => event_type, "data" => {"reference" => reference}} }
  let(:event_type) { "charge.success" }
  let(:reference) { "lago-invoice-test" }

  before do
    allow(PaymentProviders::Paystack::Client).to receive(:new).and_return(client)
  end

  context "when the event is unknown" do
    let(:event_type) { "subscription.create" }

    it "ignores the event" do
      expect(result).to be_success
      expect(PaymentProviders::Paystack::Client).not_to have_received(:new)
    end
  end

  context "when the event is a successful invoice charge" do
    let(:customer) do
      create(
        :customer,
        organization:,
        payment_provider: "paystack",
        payment_provider_code: code,
        email: "customer@example.com"
      )
    end

    let(:paystack_customer) do
      create(:paystack_customer, customer:, organization:, payment_provider:, provider_customer_id: "CUS_test")
    end

    let(:invoice) do
      create(
        :invoice,
        organization:,
        customer:,
        total_amount_cents: 50_000,
        currency: "NGN",
        ready_for_payment_processing: true
      )
    end

    let(:metadata) do
      {
        lago_customer_id: customer.id,
        lago_payable_id: invoice.id,
        lago_payable_type: invoice.class.name,
        lago_invoice_id: invoice.id,
        lago_organization_id: organization.id,
        lago_payment_provider_id: payment_provider.id,
        lago_payment_provider_code: payment_provider.code,
        payment_type: "one-time"
      }
    end

    let(:verified_transaction) do
      {
        "id" => 4_099_260_516,
        "status" => "success",
        "reference" => reference,
        "amount" => 50_000,
        "currency" => "NGN",
        "gateway_response" => "Successful",
        "metadata" => metadata.to_json,
        "authorization" => {
          "authorization_code" => "AUTH_test",
          "reusable" => true,
          "channel" => "card",
          "last4" => "4081",
          "brand" => "visa",
          "exp_month" => "12",
          "exp_year" => "2030"
        }
      }
    end

    before do
      paystack_customer
      allow(client).to receive(:verify_transaction).with(reference).and_return("data" => verified_transaction)
    end

    it "updates the payment, invoice, and saved authorization" do
      expect(result).to be_success

      payment = Payment.find_by(provider_payment_id: verified_transaction["id"].to_s)

      expect(payment).to be_present
      expect(payment).to have_attributes(
        payment_provider:,
        payment_provider_customer: paystack_customer,
        payable: invoice,
        amount_cents: 50_000,
        amount_currency: "NGN",
        status: "success",
        payable_payment_status: "succeeded"
      )

      expect(invoice.reload).to have_attributes(
        payment_status: "succeeded",
        ready_for_payment_processing: false,
        total_paid_amount_cents: 50_000
      )

      expect(paystack_customer.reload.authorization_code).to eq("AUTH_test")
      expect(paystack_customer.payment_method_id).to eq("AUTH_test")
    end

    context "when the verified transaction failed" do
      let(:event_type) { "charge.failed" }

      let(:verified_transaction) do
        {
          "id" => 4_099_260_516,
          "status" => "failed",
          "reference" => reference,
          "amount" => 50_000,
          "currency" => "NGN",
          "gateway_response" => "Declined",
          "metadata" => metadata.to_json,
          "authorization" => nil
        }
      end

      it "marks the payment and invoice failed" do
        expect(result).to be_success

        payment = Payment.find_by(provider_payment_id: verified_transaction["id"].to_s)

        expect(payment).to have_attributes(status: "failed", payable_payment_status: "failed")
        expect(invoice.reload).to have_attributes(payment_status: "failed", ready_for_payment_processing: true)
      end
    end

    context "when the verified amount does not match the Lago payable" do
      let(:verified_transaction) do
        {
          "id" => 4_099_260_516,
          "status" => "success",
          "reference" => reference,
          "amount" => 49_999,
          "currency" => "NGN",
          "metadata" => metadata.to_json,
          "authorization" => nil
        }
      end

      it "rejects the event without creating a payment" do
        expect { result }.not_to change(Payment, :count)
        expect(result).not_to be_success
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to include("Paystack amount mismatch")
      end
    end

    context "when the verified currency does not match the Lago payable" do
      let(:verified_transaction) do
        {
          "id" => 4_099_260_516,
          "status" => "success",
          "reference" => reference,
          "amount" => 50_000,
          "currency" => "GHS",
          "metadata" => metadata.to_json,
          "authorization" => nil
        }
      end

      it "rejects the event without creating a payment" do
        expect { result }.not_to change(Payment, :count)
        expect(result).not_to be_success
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to include("Paystack currency mismatch")
      end
    end

    context "when a hosted checkout resolves an existing recurring payment" do
      let!(:existing_payment) do
        create(
          :payment,
          organization:,
          customer:,
          payable: invoice,
          payment_provider:,
          payment_provider_customer: paystack_customer,
          amount_cents: 50_000,
          amount_currency: "NGN",
          provider_payment_id: reference,
          status: "requires_action",
          payable_payment_status: "processing"
        )
      end

      let(:metadata) do
        {
          lago_customer_id: customer.id,
          lago_payment_id: existing_payment.id,
          lago_payable_id: invoice.id,
          lago_payable_type: invoice.class.name,
          lago_invoice_id: invoice.id,
          lago_organization_id: organization.id,
          lago_payment_provider_id: payment_provider.id,
          lago_payment_provider_code: payment_provider.code,
          payment_type: "recurring"
        }
      end

      it "updates the existing payment instead of creating a duplicate" do
        expect { result }.not_to change(Payment, :count)
        expect(result).to be_success
        expect(existing_payment.reload).to have_attributes(
          provider_payment_id: verified_transaction["id"].to_s,
          status: "success",
          payable_payment_status: "succeeded"
        )
        expect(invoice.reload).to have_attributes(payment_status: "succeeded", ready_for_payment_processing: false)
      end
    end
  end

  context "when the event is a setup charge" do
    let(:customer) do
      create(
        :customer,
        organization:,
        payment_provider: "paystack",
        payment_provider_code: code,
        email: "customer@example.com"
      )
    end
    let(:paystack_customer) do
      create(:paystack_customer, customer:, organization:, payment_provider:, provider_customer_id: "CUS_test")
    end
    let(:metadata) do
      {
        lago_customer_id: customer.id,
        lago_paystack_customer_id: paystack_customer.id,
        lago_payment_provider_id: payment_provider.id,
        lago_payment_provider_code: payment_provider.code,
        payment_type: "setup"
      }
    end
    let(:verified_transaction) do
      {
        "id" => 4_099_260_516,
        "status" => "success",
        "reference" => reference,
        "amount" => 5000,
        "currency" => "NGN",
        "metadata" => metadata.to_json,
        "authorization" => {
          "authorization_code" => "AUTH_setup",
          "reusable" => true,
          "channel" => "card",
          "last4" => "4081",
          "brand" => "visa",
          "exp_month" => "12",
          "exp_year" => "2030"
        }
      }
    end

    before do
      paystack_customer
      allow(client).to receive(:verify_transaction).with(reference).and_return("data" => verified_transaction)
    end

    it "stores the reusable authorization without creating a payment" do
      expect { result }.not_to change(Payment, :count)
      expect(result).to be_success
      expect(paystack_customer.reload.authorization_code).to eq("AUTH_setup")
    end
  end

  context "when the event is a refund event" do
    let(:event_type) { "refund.#{refund_status}" }
    let(:refund_status) { "processed" }
    let(:reference) { nil }
    let(:event_json) do
      {
        "event" => event_type,
        "data" => {
          "id" => "3018284",
          "status" => refund_status
        }
      }
    end
    let(:customer) { create(:customer, organization:, payment_provider: "paystack", payment_provider_code: code) }
    let(:invoice) { create(:invoice, organization:, customer:, payment_status: "succeeded") }
    let(:paystack_customer) { create(:paystack_customer, customer:, organization:, payment_provider:) }
    let(:payment) do
      create(
        :payment,
        organization:,
        customer:,
        payable: invoice,
        payment_provider:,
        payment_provider_customer: paystack_customer,
        payable_payment_status: "succeeded"
      )
    end
    let(:credit_note) do
      create(:credit_note, organization:, customer:, invoice:, refund_status: :pending)
    end
    let!(:refund) do
      create(
        :refund,
        organization:,
        credit_note:,
        payment:,
        payment_provider:,
        payment_provider_customer: paystack_customer,
        provider_refund_id: "3018284",
        status: "pending"
      )
    end

    context "when Paystack marks the refund as pending" do
      let(:refund_status) { "pending" }

      it "keeps the credit note pending" do
        expect(result).to be_success
        expect(refund.reload.status).to eq("pending")
        expect(credit_note.reload).to be_pending
      end
    end

    context "when Paystack marks the refund as processing" do
      let(:refund_status) { "processing" }

      it "keeps the credit note pending" do
        expect(result).to be_success
        expect(refund.reload.status).to eq("processing")
        expect(credit_note.reload).to be_pending
      end
    end

    context "when Paystack marks the refund as needs-attention" do
      let(:refund_status) { "needs-attention" }

      it "keeps the credit note pending" do
        expect(result).to be_success
        expect(refund.reload.status).to eq("needs-attention")
        expect(credit_note.reload).to be_pending
      end
    end

    context "when Paystack marks the refund as processed" do
      it "marks the credit note as succeeded" do
        expect(result).to be_success
        expect(refund.reload.status).to eq("processed")
        expect(credit_note.reload).to be_succeeded
      end
    end

    context "when Paystack marks the refund as failed" do
      let(:refund_status) { "failed" }

      it "marks the credit note as failed" do
        expect(result).to be_success
        expect(refund.reload.status).to eq("failed")
        expect(credit_note.reload).to be_failed
      end
    end

    context "when Paystack reverses the refund" do
      let(:refund_status) { "reversed" }

      it "marks the credit note as failed" do
        expect(result).to be_success
        expect(refund.reload.status).to eq("reversed")
        expect(credit_note.reload).to be_failed
      end
    end
  end

  context "when transaction metadata belongs to another provider" do
    let(:other_provider_id) { SecureRandom.uuid }
    let(:verified_transaction) do
      {
        "status" => "success",
        "reference" => reference,
        "amount" => 50_000,
        "currency" => "NGN",
        "metadata" => {
          lago_organization_id: organization.id,
          lago_payment_provider_id: other_provider_id
        }
      }
    end

    before do
      allow(client).to receive(:verify_transaction).with(reference).and_return("data" => verified_transaction)
    end

    it "does not mutate local payments" do
      expect { result }.not_to change(Payment, :count)
      expect(result).to be_success
    end
  end
end
