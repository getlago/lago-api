# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::InvoicesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }

  before { tax }

  describe "POST /api/v1/invoices" do
    subject { post_with_token(organization, "/api/v1/invoices", {invoice: create_params}) }

    let(:add_on_first) { create(:add_on, code: "first", organization:) }
    let(:add_on_second) { create(:add_on, code: "second", amount_cents: 400, organization:) }
    let(:customer_external_id) { customer.external_id }
    let(:invoice_display_name) { "Invoice item #1" }
    let(:create_params) do
      {
        external_customer_id: customer_external_id,
        currency: "EUR",
        fees: [
          {
            add_on_code: add_on_first.code,
            invoice_display_name:,
            unit_amount_cents: 1200,
            units: 2,
            description: "desc-123",
            tax_codes: [tax.code]
          },
          {
            add_on_code: add_on_second.code
          }
        ]
      }
    end

    include_examples "requires API permission", "invoice", "write"

    it "creates an invoice" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice]).to include(
        lago_id: String,
        issuing_date: Time.current.to_date.to_s,
        invoice_type: "one_off",
        fees_amount_cents: 2800,
        taxes_amount_cents: 560,
        total_amount_cents: 3360,
        currency: "EUR"
      )

      fee = json[:invoice][:fees].find { |f| f[:item][:code] == "first" }

      expect(fee[:item][:invoice_display_name]).to eq(invoice_display_name)
      expect(json[:invoice][:applied_taxes][0][:tax_code]).to eq(tax.code)
    end

    context "when customer does not exist" do
      let(:customer_external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when add_on does not exist" do
      let(:create_params) do
        {
          external_customer_id: customer_external_id,
          currency: "EUR",
          fees: [
            {
              add_on_code: add_on_first.code,
              unit_amount_cents: 1200,
              units: 2,
              description: "desc-123"
            },
            {
              add_on_code: "invalid"
            }
          ]
        }
      end

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when skip_psp is true" do
      let(:create_params) do
        {
          external_customer_id: customer_external_id,
          currency: "EUR",
          skip_psp: true,
          fees: [
            {
              add_on_code: add_on_first.code,
              unit_amount_cents: 1200,
              units: 2
            }
          ]
        }
      end

      it "returns a success" do
        subject
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "PUT /api/v1/invoices/:id" do
    subject do
      put_with_token(organization, "/api/v1/invoices/#{invoice_id}", {invoice: update_params})
    end

    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:invoice_id) { invoice.id }

    let(:update_params) do
      {payment_status: "succeeded"}
    end

    include_examples "requires API permission", "invoice", "write"

    it "updates an invoice" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice][:lago_id]).to eq(invoice.id)
      expect(json[:invoice][:payment_status]).to eq("succeeded")
    end

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with metadata" do
      let(:update_params) do
        {
          metadata: [
            {
              key: "Hello",
              value: "Hi"
            }
          ]
        }
      end

      it "returns a success" do
        subject

        metadata = json[:invoice][:metadata]
        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:invoice][:lago_id]).to eq(invoice.id)

          expect(metadata).to be_present
          expect(metadata.first[:key]).to eq("Hello")
          expect(metadata.first[:value]).to eq("Hi")
        end
      end
    end
  end

  describe "GET /api/v1/invoices/:id" do
    subject { get_with_token(organization, "/api/v1/invoices/#{invoice_id}") }

    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:invoice_id) { invoice.id }

    include_examples "requires API permission", "invoice", "read"

    it "returns an invoice" do
      charge_filter = create(:charge_filter)
      create(:fee, invoice_id: invoice.id, charge_filter:)

      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:invoice]).to include(
          lago_id: invoice.id,
          payment_status: invoice.payment_status,
          status: invoice.status,
          customer: Hash,
          subscriptions: [],
          credits: [],
          applied_taxes: [],
          applied_invoice_custom_sections: []
        )
        expect(json[:invoice][:fees].first).to include(lago_charge_filter_id: charge_filter.id)
      end
    end

    context "when customer has an integration customer" do
      let!(:netsuite_customer) { create(:netsuite_customer, customer:) }

      it "returns an invoice with customer having integration customers" do
        subject

        expect(json[:invoice][:customer][:integration_customers].first).to include(lago_id: netsuite_customer.id)
      end
    end

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoices belongs to an other organization" do
      let(:invoice) { create(:invoice) }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoice has a fee for a deleted billable metric" do
      let(:billable_metric) { create(:billable_metric, :deleted) }
      let(:billable_metric_filter) { create(:billable_metric_filter, :deleted, billable_metric:) }
      let(:charge_filter) do
        create(:charge_filter, :deleted, charge:, properties: {amount: "10"})
      end
      let(:charge_filter_value) do
        create(
          :charge_filter_value,
          :deleted,
          charge_filter:,
          billable_metric_filter:,
          values: [billable_metric_filter.values.first]
        )
      end
      let(:fee) { create(:charge_fee, invoice:, charge_filter:, charge:) }

      let(:charge) do
        create(:standard_charge, :deleted, billable_metric:)
      end

      before do
        charge
        fee
        charge_filter_value
      end

      it "returns the invoice with the deleted resources" do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:invoice]).to include(
            lago_id: invoice.id,
            payment_status: invoice.payment_status,
            status: invoice.status,
            customer: Hash,
            subscriptions: [],
            credits: [],
            applied_taxes: []
          )

          json_fee = json[:invoice][:fees].first
          expect(json_fee[:lago_charge_filter_id]).to eq(charge_filter.id)
          expect(json_fee[:item]).to include(
            type: "charge",
            code: billable_metric.code,
            name: billable_metric.name
          )
        end
      end
    end
  end

  describe "GET /api/v1/invoices" do
    it_behaves_like "an invoice index endpoint" do
      subject { get_with_token(organization, "/api/v1/invoices", params) }

      [:external_customer_id, :customer_external_id].each do |param_name|
        context "with #{param_name} params" do
          let(:params) { {param_name => external_customer_id} }

          let!(:matching_invoice) { create(:invoice, customer:, organization:) }
          let(:external_customer_id) { customer.external_id }

          before do
            another_customer = create(:customer, organization:)
            create(:invoice, customer: another_customer, organization:)
          end

          it "returns invoices of the customer" do
            subject

            expect(response).to have_http_status(:success)
            expect(json[:invoices].count).to eq(1)
            expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
          end

          context "with deleted customer" do
            let(:params) { {external_customer_id:} }
            let(:customer) { create(:customer, :deleted, organization:) }
            let(:external_customer_id) { customer.external_id }
            let!(:matching_invoice) { create(:invoice, customer:, organization:) }

            it "returns the invoices of the customer" do
              subject

              aggregate_failures do
                expect(response).to have_http_status(:success)
                expect(json[:invoices].count).to eq(1)
                expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
                expect(json[:invoices].first[:customer][:lago_id]).to eq(customer.id)
              end
            end
          end
        end
      end
    end
  end

  describe "PUT /api/v1/invoices/:id/refresh" do
    subject { put_with_token(organization, "/api/v1/invoices/#{invoice_id}/refresh") }

    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:invoice_id) { invoice.id }

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoice is draft" do
      let(:invoice) { create(:invoice, :draft, customer:, organization:) }

      include_examples "requires API permission", "invoice", "write"

      it "updates the invoice" do
        expect { subject }.to change { invoice.reload.updated_at }
      end

      it "returns the invoice" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoice][:lago_id]).to eq(invoice.id)
      end
    end

    context "when invoice is finalized" do
      let(:invoice) { create(:invoice, customer:, organization:) }

      it "does not update the invoice" do
        expect { subject }.not_to change { invoice.reload.updated_at }
      end

      it "returns the invoice" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoice][:lago_id]).to eq(invoice.id)
      end
    end
  end

  describe "PUT /api/v1/invoices/:id/finalize" do
    subject { put_with_token(organization, "/api/v1/invoices/#{invoice_id}/finalize") }

    let(:invoice) { create(:invoice, :draft, customer:, organization:) }
    let(:invoice_id) { invoice.id }

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoice is not draft" do
      let(:invoice) { create(:invoice, customer:, status: :finalized, organization:) }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoice is draft" do
      include_examples "requires API permission", "invoice", "write"

      it "finalizes the invoice" do
        expect { subject }.to change { invoice.reload.status }.from("draft").to("finalized")
      end

      it "returns the invoice" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoice][:lago_id]).to eq(invoice.id)
      end
    end
  end

  describe "POST /api/v1/invoices/:id/void" do
    subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/void", params) }

    let!(:invoice) { create(:invoice, status:, payment_status:, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :finalized }
    let(:payment_status) { :pending }
    let(:params) { {} }

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoice is draft" do
      let(:status) { :draft }

      it "returns a method not allowed error" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end

    context "when invoice is voided" do
      let(:status) { :voided }

      it "returns a method not allowed error" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end

    context "when invoice is finalized" do
      let(:status) { :finalized }

      context "when the payment status is succeeded" do
        let(:payment_status) { :succeeded }

        it "voids the invoice" do
          expect { subject }.to change { invoice.reload.status }.from("finalized").to("voided")
        end
      end

      context "when the payment status is not succeeded" do
        let(:payment_status) { [:pending, :failed].sample }

        include_examples "requires API permission", "invoice", "write"

        it "voids the invoice" do
          expect { subject }.to change { invoice.reload.status }.from("finalized").to("voided")
        end

        it "returns the invoice" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:invoice][:lago_id]).to eq(invoice.id)
        end
      end
    end

    context "when passing credit note parameters" do
      let(:credit_amount) { 0 }
      let(:refund_amount) { 0 }
      let(:params) { {generate_credit_note: true, credit_amount: credit_amount, refund_amount: refund_amount} }

      around { |test| lago_premium!(&test) }

      it "calls the void service with all parameters" do
        allow(Invoices::VoidService).to receive(:call).with(
          invoice: instance_of(Invoice),
          params: hash_including(
            generate_credit_note: true,
            credit_amount: credit_amount,
            refund_amount: refund_amount
          )
        ).and_call_original

        subject

        expect(Invoices::VoidService).to have_received(:call).with(
          invoice: instance_of(Invoice),
          params: hash_including(
            generate_credit_note: true,
            credit_amount: credit_amount,
            refund_amount: refund_amount
          )
        )
        expect(response).to have_http_status(:success)
        expect(json[:invoice][:lago_id]).to eq(invoice.id)
        expect(json[:invoice][:status]).to eq("voided")
        expect(json[:invoice][:voided_at]).not_to be_nil
      end
    end
  end

  describe "POST /api/v1/invoices/:id/lose_dispute" do
    subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/lose_dispute") }

    let(:invoice) { create(:invoice, status:, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :draft }

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoice exists" do
      let(:invoice) { create(:invoice, customer:, organization:, status:) }

      context "when invoice is finalized" do
        let(:status) { :finalized }

        include_examples "requires API permission", "invoice", "write"

        it "marks the dispute as lost" do
          expect { subject }.to change { invoice.reload.payment_dispute_lost_at }.from(nil)
        end

        it "returns the invoice" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:invoice][:lago_id]).to eq(invoice.id)
        end
      end

      context "when invoice is voided" do
        let(:status) { :voided }

        it "marks the dispute as lost" do
          expect { subject }.to change { invoice.reload.payment_dispute_lost_at }.from(nil)
        end

        it "returns the invoice" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:invoice][:lago_id]).to eq(invoice.id)
        end
      end

      context "when invoice is draft" do
        let(:status) { :draft }

        it "returns method not allowed error" do
          subject
          expect(response).to have_http_status(:method_not_allowed)
        end
      end

      context "when invoice is generating" do
        let(:status) { :generating }

        it "returns not found error" do
          subject
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end

  describe "POST /api/v1/invoices/:id/download_pdf" do
    ["download", "download_pdf"].each do |route|
      subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/#{route}") }

      let(:invoice) { create(:invoice, customer:, organization:, status: invoice_status) }
      let(:invoice_status) { :finalized }
      let(:invoice_id) { invoice.id }

      include_examples "requires API permission", "invoice", "write"

      context "with /#{route}" do
        context "without generated pdf" do
          before do
            allow(Invoices::GeneratePdfJob).to receive(:perform_later)
          end

          it "calls generate pdf async" do
            subject

            expect(Invoices::GeneratePdfJob).to have_received(:perform_later)
          end
        end

        context "when generated pdf" do
          before do
            allow(Invoices::GeneratePdfJob).to receive(:perform_later)

            invoice.file.attach(
              io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
              filename: "invoice.pdf",
              content_type: "application/pdf"
            )
          end

          it "does not regenerate" do
            subject

            expect(Invoices::GeneratePdfJob).not_to have_received(:perform_later)
          end
        end

        context "when invoice is draft" do
          let(:invoice_status) { :draft }

          it "returns not found" do
            subject
            expect(response).to have_http_status(:not_found)
          end
        end
      end
    end
  end

  describe "POST /api/v1/invoices/:id/download_xml" do
    subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/download_xml") }

    let(:invoice) { create(:invoice, customer:, organization:, status: invoice_status) }
    let(:invoice_status) { :finalized }
    let(:invoice_id) { invoice.id }

    include_examples "requires API permission", "invoice", "write"

    context "without generated pdf" do
      before do
        allow(Invoices::GenerateXmlJob).to receive(:perform_later)
      end

      it "calls generate pdf async" do
        subject

        expect(Invoices::GenerateXmlJob).to have_received(:perform_later)
      end
    end

    context "with generated pdf" do
      before do
        allow(Invoices::GenerateXmlJob).to receive(:perform_later)

        invoice.xml_file.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.xml"))),
          filename: "invoice.xml",
          content_type: "application/xml"
        )
      end

      it "does not regenerate" do
        subject

        expect(Invoices::GenerateXmlJob).not_to have_received(:perform_later)
      end
    end

    context "when invoice is draft" do
      let(:invoice_status) { :draft }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/invoices/:id/retry_payment" do
    subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/retry_payment") }

    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:retry_service) { instance_double(Invoices::Payments::RetryService) }

    before do
      allow(Invoices::Payments::RetryService).to receive(:new).and_return(retry_service)
      allow(retry_service).to receive(:call).and_return(BaseService::Result.new)
    end

    include_examples "requires API permission", "invoice", "write"

    it "calls retry service" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(retry_service).to have_received(:call)
      end
    end

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoices belongs to an other organization" do
      let(:invoice) { create(:invoice) }

      it "returns not found" do
        subject

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/invoices/:id/retry" do
    subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/retry") }

    let!(:invoice) { create(:invoice, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:retry_service) { instance_double(Invoices::RetryService) }
    let(:result) { BaseService::Result.new }

    before do
      result.invoice = invoice

      allow(Invoices::RetryService).to receive(:new).and_return(retry_service)
      allow(retry_service).to receive(:call).and_return(result)
    end

    include_examples "requires API permission", "invoice", "write"

    it "calls retry service" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(retry_service).to have_received(:call)
      end
    end

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when invoices belongs to an other organization" do
      let(:invoice) { create(:invoice) }

      it "returns not found" do
        subject

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PUT /api/v1/invoices/:id/sync_salesforce_id" do
    subject { put_with_token(organization, "/api/v1/invoices/#{invoice_id}/sync_salesforce_id") }

    let!(:invoice) { create(:invoice, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:result) { BaseService::Result.new }

    before do
      result.invoice = invoice
      allow(Invoices::SyncSalesforceIdService).to receive(:call).and_return(result)
    end

    context "when invoice exists" do
      include_examples "requires API permission", "invoice", "write"

      it "calls sync salesforce id service" do
        subject

        expect(response).to have_http_status(:success)
        expect(Invoices::SyncSalesforceIdService).to have_received(:call)
      end
    end

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/invoices/:id/payment_url" do
    subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/payment_url") }

    let!(:invoice) { create(:invoice, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:organization) { create(:organization) }
    let(:stripe_provider) { create(:stripe_provider, organization:, code:) }
    let(:customer) { create(:customer, organization:, payment_provider_code: code) }
    let(:code) { "stripe_1" }

    before do
      create(
        :stripe_customer,
        customer_id: customer.id,
        payment_provider: stripe_provider
      )

      customer.update!(payment_provider: "stripe")

      allow(::Stripe::Checkout::Session).to receive(:create)
        .and_return({"url" => "https://example.com"})
    end

    context "when invoice exists" do
      include_examples "requires API permission", "invoice", "write"

      it "returns the generated payment url" do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:invoice_payment_details][:payment_url]).to eq("https://example.com")
        end
      end
    end

    context "when invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/invoices/preview" do
    subject { post_with_token(organization, "/api/v1/invoices/preview", preview_params) }

    let(:plan) { create(:plan, organization:) }
    let(:preview_params) do
      {
        customer: {
          name: "test 1",
          currency: "EUR",
          tax_identification_number: "123456789"
        },
        plan_code: plan.code,
        billing_time: "anniversary"
      }
    end

    before { organization.update!(premium_integrations: ["preview"]) }

    around { |test| lago_premium!(&test) }

    it "creates a preview invoice" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:invoice]).to include(
        billing_entity_code: organization.default_billing_entity.code,
        invoice_type: "subscription",
        fees_amount_cents: 100,
        taxes_amount_cents: 20,
        total_amount_cents: 120,
        currency: "EUR"
      )
    end

    context "when sending billing_entity_code" do
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:applied_tax) { create(:billing_entity_applied_tax, billing_entity:, tax:) }
      let(:preview_params) do
        {
          customer: {
            name: "test 1",
            currency: "EUR",
            tax_identification_number: "123456789"
          },
          plan_code: plan.code,
          billing_time: "anniversary",
          billing_entity_code: billing_entity.code
        }
      end

      before { applied_tax }

      it "creates a preview invoice" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoice]).to include(
          billing_entity_code: billing_entity.code,
          invoice_type: "subscription",
          fees_amount_cents: 100,
          taxes_amount_cents: 20,
          total_amount_cents: 120,
          currency: "EUR"
        )
      end

      context "when billing entity does not exist" do
        let(:preview_params) do
          {
            customer: {
              name: "test 1",
              currency: "EUR",
              tax_identification_number: "123456789"
            },
            plan_code: plan.code,
            billing_time: "anniversary",
            billing_entity_code: SecureRandom.uuid
          }
        end

        it "returns a not found error" do
          subject

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context "when subscriptions are persisted" do
      let(:customer) { create(:customer, organization:, external_id: "123456789") }
      let(:subscription1) { create(:subscription, customer:, billing_time: "anniversary", subscription_at: Time.current) }
      let(:subscription2) { create(:subscription, customer:, billing_time: "anniversary", subscription_at: Time.current) }
      let(:preview_params) do
        {
          customer: {
            external_id: "123456789"
          },
          subscriptions: {
            external_ids: [subscription1.external_id, subscription2.external_id]
          }
        }
      end

      it "creates a preview invoice" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoice]).to include(
          invoice_type: "subscription",
          fees_amount_cents: 200,
          taxes_amount_cents: 40,
          total_amount_cents: 240,
          currency: "EUR"
        )
      end
    end

    context "when subscriptions are persisted but only one belongs to the customer" do
      let(:customer) { create(:customer, organization:, external_id: "123456789") }
      let(:subscription1) { create(:subscription, billing_time: "anniversary", subscription_at: Time.current) }
      let(:subscription2) { create(:subscription, customer:, billing_time: "anniversary", subscription_at: Time.current) }
      let(:preview_params) do
        {
          customer: {
            external_id: "123456789"
          },
          subscriptions: {
            external_ids: [subscription1.external_id, subscription2.external_id]
          }
        }
      end

      it "creates a preview invoice" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoice]).to include(
          invoice_type: "subscription",
          fees_amount_cents: 100,
          taxes_amount_cents: 20,
          total_amount_cents: 120,
          currency: "EUR"
        )
      end
    end

    context "when subscriptions do not belong to the customer" do
      let(:customer) { create(:customer, organization:, external_id: "123456789") }
      let(:subscription1) { create(:subscription, billing_time: "anniversary", subscription_at: Time.current) }
      let(:subscription2) { create(:subscription, billing_time: "anniversary", subscription_at: Time.current) }
      let(:preview_params) do
        {
          customer: {
            external_id: "123456789"
          },
          subscriptions: {
            external_ids: [subscription1.external_id, subscription2.external_id]
          }
        }
      end

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when customer does not exist" do
      let(:preview_params) do
        {
          customer: {
            external_id: "unknown"
          },
          plan_code: plan.code
        }
      end

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when coupons have invalid type" do
      let(:preview_params) do
        {
          coupons: {
            code: "unknown"
          }
        }
      end

      it "returns a bad request error" do
        subject
        expect(response).to have_http_status(:bad_request)
        expect(json[:error]).to eq "coupons_must_be_an_array"
      end
    end

    context "when subscriptions have invalid type" do
      let(:preview_params) do
        {
          subscriptions: []
        }
      end

      it "returns a bad request error" do
        subject
        expect(response).to have_http_status(:bad_request)
        expect(json[:error]).to eq "subscriptions_must_be_an_object"
      end
    end
  end
end
