# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PaymentRequestsController do
  let_it_be(:organization, refind: true) { create_default(:organization, feature_flags: ["product_catalog"]) }

  let(:customer) { create(:customer, organization:) }
  let(:invoice) do
    create(:invoice, :finalized, organization:, customer:, invoice_type: :contract,
      payment_overdue: true, total_amount_cents: 1_000, total_paid_amount_cents: 200)
  end
  let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice]) }
  let(:expected_payload) do
    {
      lago_id: payment_request.id,
      lago_customer_id: customer.id,
      external_customer_id: customer.external_id,
      email: payment_request.email,
      amount_cents: payment_request.amount_cents,
      currency: payment_request.currency,
      payment_status: payment_request.payment_status,
      lago_invoice_ids: [invoice.id],
      created_at: payment_request.created_at.iso8601(6),
      updated_at: payment_request.updated_at.iso8601(6)
    }
  end

  describe "GET /api/v2/payment_requests" do
    subject(:request) { get_with_token(organization, "/api/v2/payment_requests", params) }

    let(:params) { {} }

    before do
      payment_request
      create(:payment_request, organization: create(:organization))
    end

    include_examples "requires API permission", "payment_request", "read"

    it_behaves_like "a v2 list filtered on created_at", collection: :payment_requests do
      let(:filtered_path) { "/api/v2/payment_requests" }
      let(:create_filtered_record) { ->(created_at) { create(:payment_request, organization:, created_at:) } }
    end

    it "returns only the organization's requests with the flat v2 payload" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:payment_requests]).to eq([expected_payload])
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end

    context "with legacy invoices" do
      let(:invoice) { create(:invoice, :finalized, organization:, customer:) }

      it "still lists their payment requests" do
        request

        expect(json[:payment_requests]).to eq([expected_payload])
      end
    end

    context "with several payment requests", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
      before do
        create(:payment_request, organization:, invoices: [create(:invoice, organization:)])
      end

      it "preloads customer and invoice references" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payment_requests].size).to eq(2)
      end
    end

    context "with an external_customer_id filter" do
      let(:params) { {external_customer_id: customer.external_id} }

      before { create(:payment_request, organization:) }

      it "returns only that customer's requests" do
        request

        expect(json[:payment_requests]).to eq([expected_payload])
      end

      context "with an unknown customer" do
        let(:params) { {external_customer_id: "unknown"} }

        it "returns an empty page" do
          request

          expect(json[:payment_requests]).to eq([])
          expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
        end
      end
    end

    context "with a payment_status filter" do
      let(:params) { {payment_status: "pending"} }

      before { create(:payment_request, :succeeded, organization:) }

      it "returns only matching requests" do
        request

        expect(json[:payment_requests]).to eq([expected_payload])
      end
    end

    context "with a currency filter" do
      let(:params) { {currency: "EUR"} }

      before { create(:payment_request, organization:, amount_currency: "USD") }

      it "returns only matching requests" do
        request

        expect(json[:payment_requests]).to eq([expected_payload])
      end
    end

    context "with a billing_entity_codes filter" do
      let(:params) { {billing_entity_codes: [invoice.billing_entity.code, invoice.billing_entity.code]} }
      let(:other_entity) { create(:billing_entity, organization:) }

      before do
        create(:payment_request, organization:, invoices: [create(:invoice, organization:, billing_entity: other_entity)])
      end

      it "filters by the invoices' billing entity and accepts repeated codes" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payment_requests]).to eq([expected_payload])
      end

      context "when a billing entity is archived" do
        before { invoice.billing_entity.update!(archived_at: Time.current) }

        it "still finds its payment requests" do
          request

          expect(response).to have_http_status(:ok)
          expect(json[:payment_requests]).to eq([expected_payload])
        end
      end

      context "with an unknown code" do
        let(:params) { {billing_entity_codes: [invoice.billing_entity.code, "unknown"]} }

        it "returns not found" do
          request

          expect(response).to be_v2_not_found_error("billing_entity")
        end
      end

      context "with another organization's code" do
        let(:foreign_entity) { create(:billing_entity, organization: create(:organization), code: "foreign") }
        let(:params) { {billing_entity_codes: [foreign_entity.code]} }

        it "returns not found" do
          request

          expect(response).to be_v2_not_found_error("billing_entity")
        end
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :payment_requests, model: PaymentRequest do
      let(:paginated_path) { "/api/v2/payment_requests" }
      let(:create_paginated_record) { ->(created_at) { create(:payment_request, organization:, customer:, created_at:) } }
    end
  end

  describe "GET /api/v2/payment_requests/:id" do
    subject(:request) { get_with_token(organization, "/api/v2/payment_requests/#{id}") }

    let(:id) { payment_request.id }

    include_examples "requires API permission", "payment_request", "read"

    it "returns the complete flat v2 payload" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:payment_request]).to eq(expected_payload)
    end

    context "with several invoices" do
      let(:other_invoice) { create(:invoice, :finalized, organization:, customer:) }
      let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice, other_invoice]) }

      it "returns catalog and legacy invoice references without embedding invoices" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payment_request].except(:lago_invoice_ids)).to eq(expected_payload.except(:lago_invoice_ids))
        expect(json[:payment_request][:lago_invoice_ids]).to match_array([invoice.id, other_invoice.id])
      end
    end

    context "with a deleted customer" do
      before do
        payment_request
        customer.discard!
      end

      it "retains its customer reference" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payment_request]).to eq(expected_payload)
      end
    end

    context "with a missing payment request" do
      let(:id) { SecureRandom.uuid }

      it "returns not found" do
        request

        expect(response).to be_v2_not_found_error("payment_request")
      end
    end

    context "with another organization's payment request" do
      let(:payment_request) { create(:payment_request, organization: create(:organization)) }

      it "does not expose it" do
        request

        expect(response).to be_v2_not_found_error("payment_request")
      end
    end
  end

  describe "POST /api/v2/payment_requests", :premium do
    subject(:request) { post_with_token(organization, "/api/v2/payment_requests", payment_request: params) }

    let(:params) do
      {external_customer_id: customer.external_id, email: "billing@example.com", lago_invoice_ids: [invoice.id]}
    end
    let(:payment_request) { organization.payment_requests.find(json[:payment_request][:lago_id]) }

    include_examples "requires API permission", "payment_request", "write"

    it "creates a request for the outstanding balance of a catalog invoice" do
      expect { request }.to change(PaymentRequest, :count).by(1)
        .and have_enqueued_mail(PaymentRequestMailer, :requested)

      expect(response).to have_http_status(:ok)
      expect(json[:payment_request]).to eq(expected_payload)
      expect(payment_request.amount_cents).to eq(1_000 - 200) # Invoice total minus its paid amount.
      expect(payment_request.invoices).to eq([invoice])
      expect(SendWebhookJob).to have_been_enqueued.with("payment_request.created", payment_request)
    end

    context "with a legacy invoice" do
      let(:invoice) { create(:invoice, :finalized, organization:, customer:, payment_overdue: true, total_amount_cents: 200) }

      it "still creates its payment request" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:payment_request]).to eq(expected_payload)
      end
    end

    context "without an email override" do
      let(:params) { super().except(:email) }

      it "uses the customer's email" do
        request

        expect(response).to have_http_status(:ok)
        expect(payment_request.email).to eq(customer.email)
      end
    end

    context "without a premium license" do
      before { allow(License).to receive(:premium?).and_return(false) }

      it "does not create a payment request" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with an unknown customer" do
      let(:params) { super().merge(external_customer_id: "unknown") }

      it "returns not found without creating a request" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to be_v2_not_found_error("customer")
      end
    end

    context "with another organization's customer" do
      let(:foreign_customer) { create(:customer, organization: create(:organization)) }
      let(:params) { super().merge(external_customer_id: foreign_customer.external_id) }

      it "returns not found without creating a request" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to be_v2_not_found_error("customer")
      end
    end

    context "with another customer's invoice" do
      let(:other_invoice) { create(:invoice, organization:, payment_overdue: true) }
      let(:params) { super().merge(lago_invoice_ids: [other_invoice.id]) }

      it "does not attach the foreign invoice" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to be_v2_not_found_error("invoice")
      end

      context "when the invoice belongs to another organization" do
        let(:other_invoice) { create(:invoice, organization: create(:organization), payment_overdue: true) }

        it "does not attach the foreign invoice" do
          expect { request }.not_to change(PaymentRequest, :count)

          expect(response).to be_v2_not_found_error("invoice")
        end
      end
    end

    context "without invoice IDs" do
      let(:params) { super().except(:lago_invoice_ids) }

      it "returns not found without creating a request" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to be_v2_not_found_error("invoice")
      end
    end

    context "when the invoice is not overdue" do
      before { invoice.update!(payment_overdue: false) }

      it "returns the existing invoice-state error" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "invoices_not_overdue", details: [])
      end
    end

    context "when the invoice is not ready for payment processing" do
      before { invoice.update!(ready_for_payment_processing: false) }

      it "returns the existing invoice-state error" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "invoices_not_ready_for_payment_processing", details: [])
      end
    end

    context "with invoices in different currencies" do
      let(:other_invoice) { create(:invoice, :finalized, organization:, customer:, payment_overdue: true, currency: "USD") }
      let(:params) { super().merge(lago_invoice_ids: [invoice.id, other_invoice.id]) }

      it "rejects the request" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "invoices_have_different_currencies", details: [])
      end
    end

    context "with invoices under different billing entities" do
      let(:other_entity) { create(:billing_entity, organization:) }
      let(:other_invoice) { create(:invoice, :finalized, organization:, customer:, payment_overdue: true, billing_entity: other_entity) }
      let(:params) { super().merge(lago_invoice_ids: [invoice.id, other_invoice.id]) }

      it "rejects the request" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "invoices_have_different_billing_entities", details: [])
      end
    end

    context "with an invalid payment method type" do
      let(:params) { super().merge(payment_method: {payment_method_type: "invalid"}) }

      it "returns a validation error" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "invalid_payment_method", field: "payment_method", meta: {}}])
      end
    end

    context "with another customer's payment method" do
      let(:payment_method) { create(:payment_method, organization:, customer: create(:customer, organization:)) }
      let(:params) { super().merge(payment_method: {payment_method_type: "provider", payment_method_id: payment_method.id}) }

      it "does not use the foreign payment method" do
        expect { request }.not_to change(PaymentRequest, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "invalid_payment_method", field: "payment_method", meta: {}}])
      end
    end

    context "with a Stripe payment provider" do
      let(:customer) { create(:customer, organization:, payment_provider: "stripe", payment_provider_code: "stripe") }
      let(:payment_provider) { create(:stripe_provider, organization:, code: "stripe") }
      let(:provider_customer) { create(:stripe_customer, customer:, payment_provider:) }
      let(:payment_method) { create(:payment_method, customer:, payment_provider_customer: provider_customer, provider_method_id: "pm_example") }
      let(:params) { super().merge(payment_method: {payment_method_type: "provider", payment_method_id: payment_method.id}) }
      let(:provider_status) { "succeeded" }

      before do
        create(:webhook_endpoint, organization:)
        payment_method

        stub_request(:get, "https://api.stripe.com/v1/customers/#{provider_customer.provider_customer_id}")
          .to_return(body: {id: provider_customer.provider_customer_id, object: "customer", invoice_settings: {default_payment_method: "pm_example"}}.to_json)
        stub_request(:get, "https://api.stripe.com/v1/customers/#{provider_customer.provider_customer_id}/payment_methods/pm_example")
          .to_return(body: {id: "pm_example", object: "payment_method", type: "card"}.to_json)
        stub_request(:post, "https://api.stripe.com/v1/payment_intents")
          .to_return(body: {id: "pi_example", object: "payment_intent", status: provider_status}.to_json)
      end

      it "processes the payment and generates webhooks for the catalog invoice" do
        perform_enqueued_jobs(only: [PaymentRequests::Payments::CreateJob, SendWebhookJob]) { request }

        expect(response).to have_http_status(:ok)
        payment = payment_request.payments.sole
        expect(payment.amount_cents).to eq(1_000 - 200) # Invoice total minus its paid amount.
        expect(payment.payment_method).to eq(payment_method)
        expect(payment.provider_payment_id).to eq("pi_example")
        expect(payment.payable_payment_status).to eq("succeeded")
        expect(payment_request.reload).to be_payment_succeeded
        expect(invoice.reload).to be_payment_succeeded
        expect(invoice.total_paid_amount_cents).to eq(invoice.total_amount_cents)

        created_event = organization.webhooks.find_by!(object: payment_request, webhook_type: "payment_request.created")
        expect(created_event.payload.dig("payment_request", "invoices").map { it["lago_id"] }).to eq([invoice.id])
        updated_event = organization.webhooks.find_by!(object: payment_request, webhook_type: "payment_request.payment_status_updated")
        expect(updated_event.payload.dig("payment_request", "payment_status")).to eq("succeeded")
      end

      context "when the payment fails" do
        let(:provider_status) { "requires_payment_method" }

        before do
          invoice.file.attach(io: StringIO.new("%PDF-1.4"), filename: "invoice.pdf", content_type: "application/pdf")
          stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
            .to_return(body: {id: "cs_example", object: "checkout.session", url: "https://example.com/pay"}.to_json)
        end

        it "keeps the invoice unpaid and delivers the payment-request email" do
          expect do
            perform_enqueued_jobs(only: [PaymentRequests::Payments::CreateJob, SendEmailJob]) { request }
          end.to change(ActionMailer::Base.deliveries, :count).by(1)

          expect(response).to have_http_status(:ok)
          expect(payment_request.reload).to be_payment_failed
          expect(invoice.reload).to be_payment_failed
          expect(invoice.total_paid_amount_cents).to eq(200)
          mail = ActionMailer::Base.deliveries.last
          expect(mail.to).to eq(["billing@example.com"])
          expect(mail.body.encoded).to include(invoice.number, "https://example.com/pay")
        end
      end
    end

    [nil, "invalid", []].each do |value|
      context "with #{value.inspect} as the request body" do
        let(:params) { value }

        it "returns a missing-parameter error" do
          expect { request }.not_to change(PaymentRequest, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "payment_request", meta: {}}])
        end
      end
    end
  end

  %i[index show create].each do |action|
    describe "#{action} access checks" do
      subject(:request) do
        case action
        when :index then get_with_token(organization, "/api/v2/payment_requests", params)
        when :show then get_with_token(organization, "/api/v2/payment_requests/#{SecureRandom.uuid}", params)
        when :create then post_with_token(organization, "/api/v2/payment_requests", params)
        end
      end

      let(:params) { {} }

      context "without the product catalog", product_catalog: false do
        before { organization.update!(feature_flags: []) }

        it "returns forbidden" do
          request

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
        end
      end

      context "with an unsupported expansion" do
        let(:params) { {expands: ["invoices"]} }

        it "rejects it before accessing or creating a payment request" do
          expect { request }.not_to change(PaymentRequest, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json[:code]).to eq("expand_not_supported")
        end
      end

      context "without authentication" do
        it "returns unauthorized" do
          case action
          when :index then get "/api/v2/payment_requests"
          when :show then get "/api/v2/payment_requests/#{SecureRandom.uuid}"
          when :create then post "/api/v2/payment_requests"
          end

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
