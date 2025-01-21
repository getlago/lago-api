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

  describe ".update_payment_status" do
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        provider_payment_id: invoice.id,
        status: "pending",
        payment_provider: cashfree_payment_provider
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
      expect(result.payment.payable_payment_status).to eq("succeeded")
      expect(result.invoice.reload).to have_attributes(
        payment_status: "succeeded",
        ready_for_payment_processing: false,
        total_paid_amount_cents: 200
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
        expect(result.payment.payable_payment_status).to eq("failed")
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
        expect(result.error.messages.keys).to include(:payable_payment_status)
        expect(result.error.messages[:payable_payment_status]).to include("value_is_invalid")
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
        expect(result.payment.payable_payment_status).to eq("succeeded")
        expect(result.invoice.reload).to have_attributes(
          payment_status: "succeeded",
          ready_for_payment_processing: false
        )
      end
    end
  end

  describe ".generate_payment_url" do
    let(:payment_links_response) { Net::HTTPResponse.new("1.0", "200", "OK") }
    let(:payment_links_body) { {link_url: "https://payments-test.cashfree.com/links//U1mgll3c0e9g"}.to_json }

    before do
      cashfree_payment_provider
      cashfree_customer

      allow(LagoHttpClient::Client).to receive(:new)
        .and_return(cashfree_client)
      allow(cashfree_client).to receive(:post_with_response)
        .and_return(payment_links_response)
      allow(payment_links_response).to receive(:body)
        .and_return(payment_links_body)
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

    context 'when payment url failed to generate' do
      let(:payment_links_response) { Net::HTTPResponse.new("1.0", "400", "Bad Request") }
      let(:payment_links_body) do
        {
          message: "Currency USD is not enabled",
          code: "link_post_failed",
          type: "invalid_request_error"
        }.to_json
      end

      before do
        cashfree_payment_provider
        cashfree_customer

        allow(LagoHttpClient::Client).to receive(:new)
          .and_return(cashfree_client)
        allow(cashfree_client).to receive(:post_with_response)
          .and_raise(::LagoHttpClient::HttpError.new(payment_links_response.code, payment_links_body, nil))
      end

      it 'returns a third party error' do
        result = cashfree_service.generate_payment_url

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error.third_party).to eq('Cashfree')
        expect(result.error.error_message).to eq(payment_links_body)
      end
    end
  end
end
