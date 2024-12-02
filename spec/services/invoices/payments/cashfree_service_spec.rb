# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CashfreeService, type: :service do
  subject(:cashfree_service) { described_class.new(invoice) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:cashfree_payment_provider) { create(:cashfree_provider, organization:, code:) }
  let(:cashfree_customer) { create(:cashfree_customer, customer:) }
  let(:cashfree_client) { instance_double(LagoHttpClient::Client) }

  let(:code) { "cashfree_1" }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 1000,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  describe ".call" do
    before do
      cashfree_payment_provider
      cashfree_customer

      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)
    end

    it "creates a cashfree payment", aggregate_failure: true do
      result = cashfree_service.call

      expect(result).to be_success

      expect(result.invoice).to be_payment_pending
      expect(result.invoice.payment_attempts).to eq(1)
      expect(result.invoice.reload.ready_for_payment_processing).to eq(true)

      expect(result.payment.id).to be_present
      expect(result.payment.payable).to eq(invoice)
      expect(result.payment.payment_provider).to eq(cashfree_payment_provider)
      expect(result.payment.payment_provider_customer).to eq(cashfree_customer)
      expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
      expect(result.payment.amount_currency).to eq(invoice.currency)
      expect(result.payment.status).to eq("pending")
    end

    it_behaves_like "syncs payment" do
      let(:service_call) { cashfree_service.call }
    end

    context "with no payment provider" do
      let(:cashfree_payment_provider) { nil }

      it "does not creates a payment", aggregate_failure: true do
        result = cashfree_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
      end
    end

    context "with 0 amount" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          total_amount_cents: 0,
          currency: "EUR"
        )
      end

      it "does not creates a payment", aggregate_failure: true do
        result = cashfree_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(result.invoice).to be_payment_succeeded
      end
    end

    context "when customer does not exists" do
      let(:cashfree_customer) { nil }

      it "does not creates a adyen payment", aggregate_failure: true do
        result = cashfree_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
      end
    end
  end

  describe ".update_payment_status" do
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        provider_payment_id: invoice.id,
        status: "pending"
      )
    end

    let(:cashfree_payment) do
      PaymentProviders::CashfreeProvider::CashfreePayment.new(
        id: invoice.id,
        status: "PAID",
        metadata: {}
      )
    end

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      payment
    end

    it "updates the payment and invoice payment_status" do
      result = cashfree_service.update_payment_status(
        organization_id: organization.id,
        status: cashfree_payment.status,
        cashfree_payment:
      )

      expect(result).to be_success
      expect(result.payment.status).to eq("PAID")
      expect(result.invoice.reload).to have_attributes(
        payment_status: "succeeded",
        ready_for_payment_processing: false
      )
    end

    context "when status is failed" do
      let(:cashfree_payment) do
        PaymentProviders::CashfreeProvider::CashfreePayment.new(
          id: invoice.id,
          status: "EXPIRED",
          metadata: {}
        )
      end

      it "updates the payment and invoice status" do
        result = cashfree_service.update_payment_status(
          organization_id: organization.id,
          status: cashfree_payment.status,
          cashfree_payment:
        )

        expect(result).to be_success
        expect(result.payment.status).to eq("EXPIRED")
        expect(result.invoice.reload).to have_attributes(
          payment_status: "failed",
          ready_for_payment_processing: true
        )
      end
    end

    context "when invoice is already payment_succeeded" do
      let(:cashfree_payment) do
        PaymentProviders::CashfreeProvider::CashfreePayment.new(
          id: invoice.id,
          status: %w[PARTIALLY_PAID PAID EXPIRED CANCELED].sample,
          metadata: {}
        )
      end

      before { invoice.payment_succeeded! }

      it "does not update the status of invoice and payment" do
        result = cashfree_service.update_payment_status(
          organization_id: organization.id,
          status: cashfree_payment.status,
          cashfree_payment:
        )

        expect(result).to be_success
        expect(result.invoice.payment_status).to eq("succeeded")
      end
    end

    context "with invalid status" do
      let(:cashfree_payment) do
        PaymentProviders::CashfreeProvider::CashfreePayment.new(
          id: invoice.id,
          status: "foo-bar",
          metadata: {}
        )
      end

      it "does not update the payment_status of invoice", aggregate_failures: true do
        result = cashfree_service.update_payment_status(
          organization_id: organization.id,
          status: cashfree_payment.status,
          cashfree_payment:
        )

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:payment_status)
        expect(result.error.messages[:payment_status]).to include("value_is_invalid")
      end
    end

    context "when payment is not found and it is one time payment" do
      let(:payment) { nil }

      let(:cashfree_payment) do
        PaymentProviders::CashfreeProvider::CashfreePayment.new(
          id: invoice.id,
          status: "PAID",
          metadata: {payment_type: "one-time", lago_invoice_id: invoice.id}
        )
      end

      before do
        cashfree_payment_provider
        cashfree_customer
      end

      it "creates a payment and updates invoice payment status", aggregate_failure: true do
        result = cashfree_service.update_payment_status(
          organization_id: organization.id,
          status: cashfree_payment.status,
          cashfree_payment:
        )

        expect(result).to be_success
        expect(result.payment.status).to eq("PAID")
        expect(result.invoice.reload).to have_attributes(
          payment_status: "succeeded",
          ready_for_payment_processing: false
        )
      end
    end
  end

  describe ".generate_payment_url" do
    let(:payment_links_response) { Net::HTTPResponse.new("1.0", "200", "OK") }

    before do
      cashfree_payment_provider
      cashfree_customer

      allow(LagoHttpClient::Client).to receive(:new)
        .and_return(cashfree_client)
      allow(cashfree_client).to receive(:post_with_response)
        .and_return(payment_links_response)
      allow(payment_links_response).to receive(:body)
        .and_return({link_url: "https://payments-test.cashfree.com/links//U1mgll3c0e9g"}.to_json)
    end

    it "generates payment url" do
      result = cashfree_service.generate_payment_url

      expect(result.payment_url).to be_present
    end

    context "when invoice is payment_succeeded" do
      before { invoice.payment_succeeded! }

      it "does not generate payment url" do
        result = cashfree_service.generate_payment_url

        expect(result.payment_url).to be_nil
      end
    end

    context "when invoice is voided" do
      before { invoice.voided! }

      it "does not generate payment url" do
        result = cashfree_service.generate_payment_url

        expect(result.payment_url).to be_nil
      end
    end
  end
end
