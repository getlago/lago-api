# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::CashfreeService, type: :service do
  subject(:cashfree_service) { described_class.new(payment_request) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:cashfree_payment_provider) { create(:cashfree_provider, organization:, code:) }
  let(:cashfree_customer) { create(:cashfree_customer, customer:) }
  let(:cashfree_client) { instance_double(LagoHttpClient::Client) }

  let(:code) { "cashfree_1" }

  let(:payment_request) do
    create(
      :payment_request,
      organization:,
      customer:,
      amount_cents: 799,
      amount_currency: "USD",
      invoices: [invoice_1, invoice_2]
    )
  end

  let(:invoice_1) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  let(:invoice_2) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 599,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  describe ".call" do
    before do
      cashfree_payment_provider
      cashfree_customer
    end

    it "creates a cashfree payment", aggregate_failure: true do
      result = cashfree_service.call

      expect(result).to be_success

      expect(result.payable).to be_payment_pending
      expect(result.payable.payment_attempts).to eq(1)
      expect(result.payable.reload.ready_for_payment_processing).to eq(true)

      expect(result.payment.id).to be_present
      expect(result.payment.payable).to eq(payment_request)
      expect(result.payment.payment_provider).to eq(cashfree_payment_provider)
      expect(result.payment.payment_provider_customer).to eq(cashfree_customer)
      expect(result.payment.amount_cents).to eq(payment_request.total_amount_cents)
      expect(result.payment.amount_currency).to eq(payment_request.currency)
      expect(result.payment.status).to eq("pending")
    end

    context "with no payment provider" do
      let(:cashfree_payment_provider) { nil }

      it "does not creates a payment", aggregate_failure: true do
        result = cashfree_service.call

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
      end
    end

    context "with 0 amount" do
      let(:payment_request) do
        create(
          :payment_request,
          organization:,
          customer:,
          amount_cents: 0,
          amount_currency: "EUR",
          invoices: [invoice]
        )
      end

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
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
        expect(result.payable).to be_payment_succeeded
      end
    end

    context "when customer does not exists" do
      let(:cashfree_customer) { nil }

      it "does not creates a adyen payment", aggregate_failure: true do
        result = cashfree_service.call

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
      end
    end
  end

  describe ".update_payment_status" do
    let(:payment) do
      create(
        :payment,
        payable: payment_request,
        provider_payment_id: payment_request.id,
        status: "pending"
      )
    end

    let(:cashfree_payment) do
      PaymentProviders::CashfreeProvider::CashfreePayment.new(
        id: payment_request.id,
        status: "PAID",
        metadata: {}
      )
    end

    let(:result) do
      cashfree_service.update_payment_status(
        organization_id: organization.id,
        status: cashfree_payment.status,
        cashfree_payment:
      )
    end

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      allow(SegmentTrackJob).to receive(:perform_later)
      payment
    end

    it "updates the payment and invoice payment_status" do
      expect(result).to be_success

      expect(result.payable.reload).to be_payment_succeeded
      expect(result.payable.ready_for_payment_processing).to eq(false)

      expect(invoice_1.reload).to be_payment_succeeded
      expect(invoice_1.ready_for_payment_processing).to eq(false)
      expect(invoice_2.reload).to be_payment_succeeded
      expect(invoice_2.ready_for_payment_processing).to eq(false)

      expect(result.payment.status).to eq("PAID")
    end

    it "does not send payment requested email" do
      expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
    end

    context "when the payment request belongs to a dunning campaign" do
      let(:customer) do
        create(
          :customer,
          payment_provider_code: code,
          last_dunning_campaign_attempt: 3,
          last_dunning_campaign_attempt_at: Time.zone.now
        )
      end

      let(:payment_request) do
        create(
          :payment_request,
          organization:,
          customer:,
          amount_cents: 799,
          amount_currency: "USD",
          invoices: [invoice_1, invoice_2],
          dunning_campaign: create(:dunning_campaign)
        )
      end

      it "resets the customer dunning campaign counters" do
        expect { result && customer.reload }
          .to change(customer, :last_dunning_campaign_attempt).to(0)
          .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

        expect(result).to be_success
      end

      context "when status is failed" do
        let(:cashfree_payment) do
          PaymentProviders::CashfreeProvider::CashfreePayment.new(
            id: payment_request.id,
            status: "EXPIRED",
            metadata: {}
          )
        end

        it "doest not reset the customer dunning campaign counters" do
          expect { result && customer.reload }
            .to not_change(customer, :last_dunning_campaign_attempt)
            .and not_change { customer.last_dunning_campaign_attempt_at&.to_i }

          expect(result).to be_success
        end
      end
    end

    context "when status is failed" do
      let(:cashfree_payment) do
        PaymentProviders::CashfreeProvider::CashfreePayment.new(
          id: payment_request.id,
          status: "EXPIRED",
          metadata: {}
        )
      end

      it "updates the payment, payment_request and invoices status", :aggregate_failures do
        result = cashfree_service.update_payment_status(
          organization_id: organization.id,
          status: cashfree_payment.status,
          cashfree_payment:
        )

        expect(result).to be_success
        expect(result.payment.status).to eq("EXPIRED")

        expect(result.payable.reload).to be_payment_failed
        expect(result.payable.ready_for_payment_processing).to eq(true)

        expect(invoice_1.reload).to be_payment_failed
        expect(invoice_1.ready_for_payment_processing).to eq(true)

        expect(invoice_2.reload).to be_payment_failed
        expect(invoice_2.ready_for_payment_processing).to eq(true)
      end

      it "sends a payment requested email" do
        expect { result }
          .to have_enqueued_mail(PaymentRequestMailer, :requested)
          .with(params: {payment_request:}, args: [])
      end
    end

    context "when payment_request and invoices is already payment_succeeded" do
      let(:cashfree_payment) do
        PaymentProviders::CashfreeProvider::CashfreePayment.new(
          id: payment_request.id,
          status: %w[PARTIALLY_PAID PAID EXPIRED CANCELED].sample,
          metadata: {}
        )
      end

      before do
        payment_request.payment_succeeded!
        invoice_1.payment_succeeded!
        invoice_2.payment_succeeded!
      end

      it "does not update the status of invoices, payment_request and payment" do
        expect { result }
          .to not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and not_change { payment_request.reload.payment_status }
          .and not_change { payment.reload.status }

        expect(result).to be_success
      end

      it "does not send payment requested email" do
        expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end
    end

    context "with invalid status" do
      let(:cashfree_payment) do
        PaymentProviders::CashfreeProvider::CashfreePayment.new(
          id: payment_request.id,
          status: "foo-bar",
          metadata: {}
        )
      end

      it "does not update the payment_status of payment_request, invoices and payment" do
        expect { result }
          .to not_change { payment_request.reload.payment_status }
          .and not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and change { payment.reload.status }.to("foo-bar")
      end

      it "returns an error", :aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:payment_status)
        expect(result.error.messages[:payment_status]).to include("value_is_invalid")
      end

      it "does not send payment requested email" do
        expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end
    end

    context "when payment is not found and it is one time payment" do
      let(:payment) { nil }

      let(:cashfree_payment) do
        PaymentProviders::CashfreeProvider::CashfreePayment.new(
          id: payment_request.id,
          status: "PAID",
          metadata: {
            payment_type: "one-time",
            lago_payable_id: payment_request.id,
            lago_payable_type: "PaymentRequest"
          }
        )
      end

      before do
        cashfree_payment_provider
        cashfree_customer
      end

      it "creates a payment and updates invoice payment status", aggregate_failure: true do
        expect(result).to be_success
        expect(result.payment.status).to eq("PAID")

        expect(result.payable).to be_payment_succeeded
        expect(result.payable.ready_for_payment_processing).to eq(false)

        expect(invoice_1.reload).to be_payment_succeeded
        expect(invoice_1.ready_for_payment_processing).to eq(false)

        expect(invoice_2.reload).to be_payment_succeeded
        expect(invoice_2.ready_for_payment_processing).to eq(false)
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
      before { payment_request.payment_succeeded! }

      it "does not generate payment url" do
        result = cashfree_service.generate_payment_url

        expect(result.payment_url).to be_nil
      end
    end
  end
end
