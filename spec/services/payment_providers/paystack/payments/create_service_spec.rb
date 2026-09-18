# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Paystack::Payments::CreateService do
  subject(:result) { described_class.call(payment:, reference:, metadata:) }

  let(:organization) { create(:organization) }
  let(:code) { "paystack_1" }
  let(:payment_provider) { create(:paystack_provider, organization:, code:) }
  let(:currency) { "NGN" }
  let(:customer) { create(:customer, organization:, payment_provider: "paystack", payment_provider_code: code, email: "customer@example.com") }
  let(:paystack_customer) do
    create(
      :paystack_customer,
      organization:,
      customer:,
      payment_provider:,
      provider_customer_id: "CUS_test",
      authorization_code: "AUTH_test",
      payment_method_id: "AUTH_test"
    )
  end
  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 50_000,
      currency:,
      ready_for_payment_processing: true
    )
  end
  let(:payment) do
    create(
      :payment,
      organization:,
      customer:,
      payable:,
      payment_provider:,
      payment_provider_customer: paystack_customer,
      amount_cents: 50_000,
      amount_currency: invoice.currency,
      status: "pending",
      payable_payment_status: "pending"
    )
  end
  let(:payable) { invoice }
  let(:reference) { "Entity Name - Invoice INV-001" }
  let(:provider_reference) { "lago-payment-#{payment.id}" }
  let(:metadata) { {lago_invoice_id: invoice.id} }
  let(:client) { instance_double(PaymentProviders::Paystack::Client) }

  before do
    allow(PaymentProviders::Paystack::Client).to receive(:new).and_return(client)
    allow(client).to receive(:charge_authorization).and_return(
      "message" => "Success",
      "data" => {
        "id" => 4_099_260_516,
        "status" => "success",
        "reference" => provider_reference,
        "gateway_response" => "Successful",
        "authorization" => {
          "authorization_code" => "AUTH_new",
          "reusable" => true,
          "channel" => "card",
          "last4" => "4081",
          "brand" => "visa",
          "exp_month" => "12",
          "exp_year" => "2030"
        }
      }
    )
  end

  it "charges the saved authorization and updates the payment" do
    expect(result).to be_success
    expect(result.payment.reload).to have_attributes(
      provider_payment_id: "4099260516",
      status: "success",
      payable_payment_status: "succeeded"
    )
    expect(paystack_customer.reload.authorization_code).to eq("AUTH_new")
    expect(client).to have_received(:charge_authorization).with(
      hash_including(
        amount: 50_000,
        authorization_code: "AUTH_test",
        reference: provider_reference,
        currency: "NGN"
      )
    )
  end

  context "when Paystack returns a failed status" do
    before do
      allow(client).to receive(:charge_authorization).and_return(
        "message" => "Failed",
        "data" => {
          "id" => 4_099_260_516,
          "status" => "failed",
          "reference" => provider_reference,
          "gateway_response" => "Declined"
        }
      )
    end

    it "marks the payment failed and returns a service failure" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("paystack_error")
      expect(payment.reload).to have_attributes(status: "failed", payable_payment_status: "failed")
    end
  end

  context "when Paystack rejects a duplicate reference" do
    let(:http_status) { 400 }
    let(:duplicate_message) { "Duplicate Transaction Reference" }
    let(:error_code) { nil }
    let(:charge_request) do
      stub_request(:post, "https://api.paystack.co/transaction/charge_authorization")
        .with { |request| JSON.parse(request.body)["reference"] == provider_reference }
        .to_return(status: http_status, body: {status: false, message: duplicate_message, code: error_code}.compact.to_json)
    end
    let(:verified_status) { "success" }
    let(:verified_metadata) do
      {
        lago_payment_id: payment.id,
        lago_payable_id: payable.id,
        lago_payable_type: payable.class.name,
        lago_customer_id: customer.id,
        lago_organization_id: organization.id,
        lago_payment_provider_id: payment_provider.id,
        payment_type: "recurring"
      }
    end
    let(:verified_transaction) do
      {
        "id" => 4_099_260_516,
        "status" => verified_status,
        "reference" => provider_reference,
        "amount" => payment.amount_cents,
        "currency" => currency,
        "metadata" => verified_metadata,
        "authorization" => nil
      }
    end
    let(:verification_request) do
      stub_request(:get, "https://api.paystack.co/transaction/verify/#{provider_reference}")
        .to_return(status: 200, body: {status: true, data: verified_transaction}.to_json)
    end

    before do
      allow(PaymentProviders::Paystack::Client).to receive(:new).and_call_original
      charge_request
      verification_request
    end

    it "recovers the original payment from verification" do
      expect { result }.not_to change(Payment, :count)
      expect(result).to be_success
      expect(payment.reload).to have_attributes(provider_payment_id: "4099260516", payable_payment_status: "succeeded")
      expect(charge_request).to have_been_requested.once
      expect(verification_request).to have_been_requested.once
    end

    context "when the error is returned with HTTP 200" do
      let(:http_status) { 200 }
      let(:duplicate_message) { "Duplicate charge request for reference" }

      it "verifies the original charge" do
        expect(result).to be_success
        expect(payment.reload).to be_succeeded
        expect(verification_request).to have_been_requested.once
      end
    end

    [400, 200].each do |status|
      context "when HTTP #{status} returns a duplicate code with an unfamiliar message" do
        let(:http_status) { status }
        let(:duplicate_message) { "The reference has already been used" }
        let(:error_code) { "duplicate_reference" }

        it "recovers the original payment without another charge" do
          expect { result }.not_to change(Payment, :count)
          expect(result).to be_success
          expect(payment.reload).to have_attributes(provider_payment_id: "4099260516", payable_payment_status: "succeeded")
          expect(charge_request).to have_been_requested.once
          expect(verification_request).to have_been_requested.once
        end
      end
    end

    context "when the invoice job retries after an uncertain charge response" do
      subject(:charge_invoice) { Invoices::Payments::CreateService.call!(invoice:, payment_provider: :paystack) }

      let(:charge_request) do
        stub_request(:post, "https://api.paystack.co/transaction/charge_authorization")
          .with { |request| JSON.parse(request.body)["reference"] == provider_reference }
          .to_return(status: 502, body: "Bad gateway").then
          .to_return(status: 400, body: {status: false, message: duplicate_message}.to_json)
      end

      it "reuses the pending payment and settles it without a webhook" do
        expect { charge_invoice }.to raise_error(RetriableError)
        expect(payment.reload).to be_pending
        expect(invoice.reload).not_to be_payment_failed

        recovered = Invoices::Payments::CreateService.call!(invoice:, payment_provider: :paystack)

        expect(recovered.payment.id).to eq(payment.id)
        expect(invoice.reload).to have_attributes(payment_status: "succeeded", total_paid_amount_cents: 50_000)
        expect(invoice.payments.count).to eq(1)
        expect(charge_request).to have_been_requested.twice

        expect do
          PaymentProviders::Paystack::HandleEventService.call!(
            organization:,
            payment_provider:,
            event_json: {"event" => "charge.success", "data" => {"reference" => provider_reference}}
          )
        end.not_to change { [invoice.reload.total_paid_amount_cents, invoice.payments.count] }
      end
    end

    context "when the verified transaction failed" do
      let(:verified_status) { "failed" }

      it "records the confirmed failure" do
        expect(result).not_to be_success
        expect(payment.reload).to be_failed
        expect(verification_request).to have_been_requested.once
      end
    end

    %w[pending processing ongoing queued].each do |status|
      context "when the verified transaction is #{status}" do
        let(:verified_status) { status }

        it "keeps the payment pending and retries verification without another charge" do
          expect { result }.to raise_error(RetriableError)
          expect(payment.reload).to be_pending
          expect do
            described_class.call(payment:, reference:, metadata:)
          end.to raise_error(RetriableError)
          expect(charge_request).to have_been_requested.once
          expect(verification_request).to have_been_requested.twice
        end
      end
    end

    context "when verification is temporarily unavailable" do
      let(:verification_request) do
        stub_request(:get, "https://api.paystack.co/transaction/verify/#{provider_reference}")
          .to_return(status: 503, body: "Unavailable").then
          .to_return(status: 200, body: {status: true, data: verified_transaction}.to_json)
      end

      it "retries verification and then settles the same payment" do
        expect { result }.to raise_error(RetriableError)
        expect(payment.reload).to be_pending
        expect(described_class.call(payment:, reference:, metadata:)).to be_success
        expect(payment.reload).to be_succeeded
        expect(charge_request).to have_been_requested.once
        expect(verification_request).to have_been_requested.twice
      end
    end

    context "when verification times out" do
      let(:verification_request) do
        stub_request(:get, "https://api.paystack.co/transaction/verify/#{provider_reference}").to_timeout
      end

      it "leaves the payment pending for a bounded retry" do
        expect { result }.to raise_error(RetriableError)
        expect(payment.reload).to be_pending
      end
    end

    context "when verification returns invalid JSON" do
      let(:verification_request) do
        stub_request(:get, "https://api.paystack.co/transaction/verify/#{provider_reference}")
          .to_return(status: 200, body: "not-json")
      end

      it "leaves the payment pending for a bounded retry" do
        expect { result }.to raise_error(RetriableError)
        expect(payment.reload).to be_pending
      end
    end

    context "when verification returns metadata as JSON" do
      let(:verified_transaction) { super().merge("metadata" => verified_metadata.to_json) }

      it "recovers the payment" do
        expect(result).to be_success
        expect(payment.reload).to be_succeeded
      end
    end

    context "when a webhook settles the payment during verification" do
      let(:verified_status) { "failed" }
      let(:verification_request) do
        stub_request(:get, "https://api.paystack.co/transaction/verify/#{provider_reference}")
          .to_return do
            Payment.find(payment.id).update!(status: "success", payable_payment_status: "succeeded")
            {status: 200, body: {status: true, data: verified_transaction}.to_json}
          end
      end

      it "does not overwrite the recorded success with a stale failure" do
        expect(result).to be_success
        expect(payment.reload).to be_succeeded
      end
    end

    [
      [Invoices::Payments::CreateJob, :invoice],
      [PaymentRequests::Payments::CreateJob, :payable]
    ].each do |job_class, argument|
      context "when #{job_class} receives an unresolved transaction" do
        let(:verified_status) { "pending" }
        let(:payable) do
          if argument == :invoice
            invoice
          else
            create(:payment_request, organization:, customer:, amount_cents: 50_000, amount_currency: currency, invoices: [invoice])
          end
        end
        let(:job) { job_class.new(**{argument => payable, :payment_provider => :paystack}) }

        it "schedules a retry without failing the payment or sending a failure email" do
          expect { job.perform_now }.to have_enqueued_job(job_class)
          expect(payment.reload).to be_pending
          expect(payable.reload).not_to be_payment_failed
          expect(ActionMailer::MailDeliveryJob).not_to have_been_enqueued
        end

        context "when the retry limit is reached" do
          before { job.exception_executions["[RetriableError]"] = 19 }

          it "raises without recording a payment failure or scheduling another retry" do
            expect { job.perform_now }.to raise_error(RetriableError)
            expect(payment.reload).to be_pending
            expect(payable.reload).not_to be_payment_failed
            expect(job_class).not_to have_been_enqueued
          end
        end
      end
    end

    {
      "reference" => "another-reference",
      "id" => nil,
      "amount" => 49_999,
      "currency" => "USD",
      "metadata" => {},
      "status" => "unknown"
    }.each do |field, value|
      context "when verification returns an invalid #{field}" do
        let(:verified_transaction) { super().merge(field => value) }

        it "does not settle or fail the payment" do
          expect { result }.to raise_error(RetriableError)
          expect(payment.reload).to be_pending
        end
      end
    end

    %i[lago_payment_id lago_customer_id lago_organization_id lago_payment_provider_id].each do |key|
      context "when verification has a different #{key}" do
        let(:verified_metadata) { super().merge(key => SecureRandom.uuid) }

        it "does not settle or fail the payment" do
          expect { result }.to raise_error(RetriableError)
          expect(payment.reload).to be_pending
        end
      end
    end

    context "when Paystack rejects the request for another reason" do
      let(:duplicate_message) { "Invalid authorization code" }
      let(:error_code) { "invalid_authorization" }

      it "keeps the normal error handling without verifying a transaction" do
        expect(result).not_to be_success
        expect(payment.reload).to be_failed
        expect(verification_request).not_to have_been_requested
      end
    end
  end

  context "when the provider customer has no reusable authorization" do
    let(:paystack_customer) do
      create(
        :paystack_customer,
        organization:,
        customer:,
        payment_provider:,
        provider_customer_id: "CUS_test"
      )
    end

    before do
      allow(client).to receive(:initialize_transaction).and_return(
        "data" => {
          "authorization_url" => "https://checkout.paystack.com/test",
          "access_code" => "ACCESS_test",
          "reference" => provider_reference
        }
      )
    end

    it "creates a hosted checkout payment that requires customer action" do
      expect(result).to be_success
      expect(result.payment.reload).to have_attributes(
        status: "requires_action",
        payable_payment_status: "processing"
      )
      expect(result.payment.provider_payment_data).to include(
        "authorization_url" => "https://checkout.paystack.com/test",
        "access_code" => "ACCESS_test",
        "reference" => provider_reference
      )
      expect(client).not_to have_received(:charge_authorization)
      expect(client).to have_received(:initialize_transaction).with(
        hash_including(
          amount: 50_000,
          currency: "NGN",
          reference: provider_reference,
          callback_url: payment_provider.success_redirect_url
        )
      )
      expect(SendWebhookJob).to have_been_enqueued.with("payment.requires_action", result.payment)
    end
  end

  context "when the payment has a selected payment method" do
    let(:payment_method) do
      create(
        :payment_method,
        organization:,
        customer:,
        payment_provider:,
        payment_provider_customer: paystack_customer,
        provider_method_id: "AUTH_multiple"
      )
    end

    before do
      payment.update!(payment_method:)
    end

    it "uses the selected payment method authorization" do
      expect(result).to be_success
      expect(client).to have_received(:charge_authorization).with(
        hash_including(authorization_code: "AUTH_multiple")
      )
    end
  end

  context "when the payment currency is unsupported" do
    let(:currency) { "EUR" }

    it "does not call Paystack" do
      expect(result).not_to be_success
      expect(client).not_to have_received(:charge_authorization)
      expect(payment.reload).to have_attributes(status: "failed", payable_payment_status: "failed")
    end
  end
end
