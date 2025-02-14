# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::InvoicesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }

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
    subject { get_with_token(organization, "/api/v1/invoices", params) }

    let(:customer) { create(:customer, organization:) }

    context "without params" do
      let(:params) { {} }
      let!(:invoice) { create(:invoice, :draft, customer:, organization:) }

      include_examples "requires API permission", "invoice", "read"

      it "returns invoices" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first).to include(
          lago_id: invoice.id,
          payment_status: invoice.payment_status,
          status: invoice.status
        )
      end

      context "when customer has an integration customer" do
        let!(:netsuite_customer) { create(:netsuite_customer, customer:) }

        it "returns an invoice with customer having integration customers" do
          subject

          expect(json[:invoices].first[:customer][:integration_customers].first)
            .to include(lago_id: netsuite_customer.id)
        end
      end
    end

    context "with pagination" do
      let(:params) { {page: 1, per_page: 1} }

      before do
        create(:invoice, :draft, customer:, organization:)
        create(:invoice, customer:, organization:)
      end

      it "returns invoices with correct meta data" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:invoices].count).to eq(1)
        expect(json[:meta]).to include(
          current_page: 1,
          next_page: 2,
          prev_page: nil,
          total_pages: 2,
          total_count: 2
        )
      end
    end

    context "with issuing_date params" do
      let(:params) do
        {issuing_date_from: 2.days.ago.to_date, issuing_date_to: Date.tomorrow.to_date}
      end

      let!(:matching_invoice) do
        create(:invoice, customer:, issuing_date: 1.day.ago.to_date, organization:)
      end

      before { create(:invoice, customer:, issuing_date: 3.days.ago.to_date, organization:) }

      it "returns invoices with correct issuing date" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
      end
    end

    context "with external_customer_id params" do
      let(:params) { {external_customer_id:} }

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

    context "with status params" do
      let(:params) { {status: "finalized"} }
      let!(:matching_invoice) { create(:invoice, customer:, organization:) }

      before { create(:invoice, :draft, customer:, organization:) }

      it "returns invoices for the given status" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
      end
    end

    context "with payment status param" do
      let(:params) { {payment_status: "pending"} }

      let!(:matching_invoice) do
        create(:invoice, customer:, payment_status: :pending, organization:)
      end

      before do
        create(:invoice, customer:, payment_status: :succeeded, organization:)
        create(:invoice, customer:, payment_status: :failed, organization:)
      end

      it "returns invoices with correct payment status" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
      end
    end

    context "with payment overdue param" do
      let(:params) { {payment_overdue: true} }

      let!(:matching_invoice) do
        create(:invoice, customer:, payment_overdue: true, organization:)
      end

      before { create(:invoice, customer:, organization:) }

      it "returns payment overdue invoices" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
      end
    end

    context "with invoice type param" do
      let(:params) { {invoice_type: "advance_charges"} }

      let!(:matching_invoice) do
        create(:invoice, customer:, invoice_type: :advance_charges, organization:)
      end

      before { create(:invoice, customer:, invoice_type: :add_on, organization:) }

      it "returns invoices with correct invoice type" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
      end
    end

    context "with currency param" do
      let(:params) { {currency: "USD"} }

      let!(:matching_invoice) { create(:invoice, customer:, currency: "USD", organization:) }

      before { create(:invoice, customer:, currency: "EUR", organization:) }

      it "returns invoices with correct currency" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
      end
    end

    context "with payment dispute lost param" do
      let(:params) { {payment_dispute_lost: true} }

      let!(:matching_invoice) { create(:invoice, :dispute_lost, customer:, organization:) }

      before { create(:invoice, customer:, organization:) }

      it "returns invoices with payment dispute lost" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
      end
    end

    context "with search term param" do
      let(:params) { {search_term: matching_invoice.number} }

      let!(:matching_invoice) do
        create(:invoice, customer:, number: SecureRandom.uuid, organization:)
      end

      before { create(:invoice, customer:, number: "not-relevant-number", organization:) }

      it "returns invoices matching the search terms" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(matching_invoice.id)
      end
    end

    context "with amount filters" do
      let(:params) do
        {
          amount_from: invoices.second.total_amount_cents,
          amount_to: invoices.fourth.total_amount_cents
        }
      end

      let!(:invoices) do
        (1..5).to_a.map do |i|
          create(:invoice, total_amount_cents: i.succ * 1_000, organization:)
        end # from smallest to biggest
      end

      it "returns invoices with total cents amount in provided range" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].pluck(:lago_id)).to match_array invoices[1..3].pluck(:id)
      end
    end

    context "with metadata filters" do
      let(:params) do
        metadata = matching_invoice.metadata.first

        {
          metadata: {
            metadata.key => metadata.value
          }
        }
      end

      let(:matching_invoice) { create(:invoice, organization:) }

      before do
        create(:invoice_metadata, invoice: matching_invoice)
        create(:invoice, organization:)
      end

      it "returns invoices with matching metadata filters" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].pluck(:lago_id)).to contain_exactly matching_invoice.id
      end
    end

    context "with self billed filters" do
      let(:params) { {self_billed: true} }

      let(:self_billed_invoice) do
        create(:invoice, :self_billed, customer:, organization:)
      end

      let(:non_self_billed_invoice) do
        create(:invoice, customer:, organization:)
      end

      before do
        self_billed_invoice
        non_self_billed_invoice
      end

      it "returns self billed invoices" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:invoices].count).to eq(1)
        expect(json[:invoices].first[:lago_id]).to eq(self_billed_invoice.id)
      end

      context "when self billed is false" do
        let(:params) { {self_billed: false} }

        it "returns non self billed invoices" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:invoices].count).to eq(1)
          expect(json[:invoices].first[:lago_id]).to eq(non_self_billed_invoice.id)
        end
      end

      context "when self billed is nil" do
        let(:params) { {self_billed: nil} }

        it "returns all invoices" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:invoices].count).to eq(2)
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
    subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/void") }

    let!(:invoice) { create(:invoice, status:, payment_status:, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :finalized }
    let(:payment_status) { :pending }

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

        it "returns a method not allowed error" do
          subject
          expect(response).to have_http_status(:method_not_allowed)
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

        it "returns method not allowed error" do
          subject
          expect(response).to have_http_status(:method_not_allowed)
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

  describe "POST /api/v1/invoices/:id/download" do
    subject { post_with_token(organization, "/api/v1/invoices/#{invoice_id}/download") }

    let(:invoice) { create(:invoice, :draft, customer:, organization:) }
    let(:invoice_id) { invoice.id }

    include_examples "requires API permission", "invoice", "write"

    context "when invoice is draft" do
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
    let(:sync_salesforce_service) { instance_double(Invoices::SyncSalesforceIdService) }
    let(:result) { BaseService::Result.new }

    before do
      result.invoice = invoice
      allow(Invoices::SyncSalesforceIdService).to receive(:new).and_return(sync_salesforce_service)
      allow(sync_salesforce_service).to receive(:call).and_return(result)
    end

    context "when invoice exists" do
      include_examples "requires API permission", "invoice", "write"

      it "calls sync salesforce id service" do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(sync_salesforce_service).to have_received(:call)
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

    around { |test| lago_premium!(&test) }

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
      let(:customer) { create(:customer, organization:, external_id: '123456789') }
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
          currency: 'EUR'
        )
      end
    end

    context "when subscriptions do not belong to the customer" do
      let(:customer) { create(:customer, organization:, external_id: '123456789') }
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

    context "when params have invalid structure" do
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
  end
end
