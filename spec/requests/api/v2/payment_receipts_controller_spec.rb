# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PaymentReceiptsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
  let(:payment_receipt) { create(:payment_receipt, organization:, payment: create(:payment, payable: invoice)) }

  describe "GET /api/v2/payment_receipts" do
    subject { get_with_token(organization, "/api/v2/payment_receipts", params) }

    let(:params) { {} }
    let(:legacy_invoice) { create(:invoice, organization:, customer:, invoice_type: :subscription) }
    let(:legacy_receipt) { create(:payment_receipt, organization:, payment: create(:payment, payable: legacy_invoice)) }

    before do
      payment_receipt
      legacy_receipt
    end

    include_examples "requires API permission", "payment_receipt", "read"

    it "lists every receipt of the organization, as the v2 payments do" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_receipts].map { it[:lago_id] }).to match_array([payment_receipt.id, legacy_receipt.id])
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :payment_receipts, model: PaymentReceipt do
      let(:paginated_path) { "/api/v2/payment_receipts" }
      let(:create_paginated_record) do
        ->(created_at) { create(:payment_receipt, organization:, created_at:, payment: create(:payment, payable: create(:invoice, organization:, customer:))) }
      end
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :payment_receipts do
      let(:filtered_path) { "/api/v2/payment_receipts" }
      let(:create_filtered_record) do
        ->(created_at) { create(:payment_receipt, organization:, created_at:, payment: create(:payment, payable: create(:invoice, organization:, customer:))) }
      end
    end

    context "with an invoice_id" do
      let(:params) { {invoice_id: other_invoice.id} }
      let(:other_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
      let(:other_receipt) { create(:payment_receipt, organization:, payment: create(:payment, payable: other_invoice)) }

      before { other_receipt }

      it "lists the receipts of that invoice" do
        subject

        expect(json[:payment_receipts].map { it[:lago_id] }).to eq([other_receipt.id])
      end
    end

    context "with an invalid invoice_id" do
      let(:params) { {invoice_id: "not-a-uuid"} }

      it "returns a validation error on the filter" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "value_is_invalid", field: "invoice_id", meta: {}}]
        )
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "GET /api/v2/payment_receipts/:id" do
    subject { get_with_token(organization, "/api/v2/payment_receipts/#{payment_receipt_id}") }

    let(:payment_receipt_id) { payment_receipt.id }

    include_examples "requires API permission", "payment_receipt", "read"

    it "returns the payment receipt" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_receipt]).to include(
        lago_id: payment_receipt.id,
        number: payment_receipt.number,
        lago_payment_id: payment_receipt.payment_id
      )
    end

    context "with generated documents" do
      around { |example| freeze_time { example.run } }

      before do
        payment_receipt.file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.pdf")), filename: "receipt.pdf", content_type: "application/pdf")
        payment_receipt.xml_file.attach(io: File.open(Rails.root.join("spec/fixtures/blank.xml")), filename: "receipt.xml", content_type: "application/xml")
      end

      it "returns document links with their expiry" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:payment_receipt]).to eq(
          lago_id: payment_receipt.id,
          number: payment_receipt.number,
          lago_payment_id: payment_receipt.payment_id,
          pdf_url: payment_receipt.file_url,
          pdf_url_expires_at: payment_receipt.file_url_expires_at.iso8601(6),
          xml_url: payment_receipt.xml_url,
          xml_url_expires_at: payment_receipt.xml_url_expires_at.iso8601(6),
          created_at: payment_receipt.created_at.iso8601(6),
          updated_at: payment_receipt.updated_at.iso8601(6)
        )
      end
    end

    context "when the receipt pays a legacy invoice" do
      let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :subscription) }

      it "returns it, as the v2 payments do" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:payment_receipt][:lago_id]).to eq(payment_receipt.id)
      end
    end

    context "when the receipt belongs to another organization" do
      let(:other_invoice) { create(:invoice, invoice_type: :contract) }
      let(:payment_receipt_id) do
        create(:payment_receipt, organization: other_invoice.organization, payment: create(:payment, payable: other_invoice)).id
      end

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("payment_receipt")
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
