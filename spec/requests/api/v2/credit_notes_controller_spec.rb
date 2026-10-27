# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::CreditNotesController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) do
    create(:invoice, organization:, customer:, payment_status: "succeeded", currency: "EUR", fees_amount_cents: 100, total_amount_cents: 120, total_paid_amount_cents: 120)
  end
  let(:credit_note) { create(:credit_note, invoice:, customer:) }

  before { organization.enable_feature_flag!(:product_catalog) }

  describe "GET /api/v2/credit_notes/:id" do
    subject(:request) { get_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}") }

    include_examples "requires API permission", "credit_note", "read"

    it "returns the v2 credit note payload" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:credit_note]).to include(lago_id: credit_note.id, lago_invoice_id: invoice.id)
      expect(json[:credit_note][:created_at]).to eq(credit_note.created_at.iso8601(6))
    end

    context "when the product catalog is disabled" do
      before { organization.disable_feature_flag!(:product_catalog) }

      it "returns a forbidden error" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the credit note belongs to another organization" do
      let(:credit_note) { create(:credit_note) }

      it "returns not found" do
        request

        expect(response).to have_http_status(:not_found)
        expect(response).to be_not_found_error("credit_note")
      end
    end

    context "with expanded items and taxes" do
      subject(:request) { get_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}", expands: %w[items applied_taxes]) }

      let(:item) { create(:credit_note_item, credit_note:, amount_cents: 25) }
      let(:tax) { create(:credit_note_applied_tax, credit_note:, base_amount_cents: 25, amount_cents: 5) }

      before do
        item
        tax
      end

      it "returns the selected fee and tax details with v2 names" do
        request

        expect(json[:credit_note][:items]).to eq([{lago_fee_id: item.fee_id, amount_cents: 25}])
        expect(json[:credit_note][:applied_taxes]).to eq([{
          lago_tax_id: tax.tax_id,
          tax_name: tax.tax_name,
          tax_code: tax.tax_code,
          tax_rate: tax.tax_rate,
          tax_description: tax.tax_description,
          base_amount_cents: 25,
          amount_cents: 5,
          currency: "EUR"
        }])
      end
    end
  end

  describe "GET /api/v2/credit_notes" do
    subject(:request) { get_with_token(organization, "/api/v2/credit_notes", params) }

    let(:params) { {} }
    let(:credit_notes) { create_list(:credit_note, 3, invoice:, customer:) }

    before { credit_notes }

    include_examples "requires API permission", "credit_note", "read"

    it "returns a cursor page" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:credit_notes].map { it[:lago_id] }).to eq(credit_notes.sort_by { |note| [-note.created_at.to_f, note.id] }.map(&:id))
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :credit_notes, model: CreditNote do
      let(:paginated_path) { "/api/v2/credit_notes" }
      let(:create_paginated_record) { ->(created_at) { create(:credit_note, invoice:, customer:, created_at:) } }
    end

    context "with invalid cursor parameters" do
      let(:params) { {page: 2} }

      it "rejects offset pagination" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_pagination_parameter")
      end
    end
  end

  describe "POST /api/v2/credit_notes/estimate", :premium do
    subject(:request) do
      post_with_token(organization, "/api/v2/credit_notes/estimate", credit_note: {invoice_id: invoice.id, items: [{fee_id: fee.id, amount_cents: 50}]})
    end

    let(:fee) { create(:fee, invoice:, amount_cents: 100) }

    include_examples "requires API permission", "credit_note", "write"

    it "returns selected amounts without creating a credit note" do
      expect { request }.not_to change(CreditNote, :count)

      expect(response).to have_http_status(:ok)
      expect(json).to eq(estimated_credit_note: {
        lago_invoice_id: invoice.id,
        invoice_number: invoice.number,
        currency: "EUR",
        sub_total_excluding_taxes_amount_cents: 50,
        taxes_amount_cents: 0,
        sub_total_including_taxes_amount_cents: 50,
        total_amount_cents: 50,
        max_creditable_amount_cents: 50,
        max_refundable_amount_cents: 0,
        items: [{lago_fee_id: fee.id, amount_cents: 50}],
        applied_taxes: []
      })
    end

    context "when the product catalog is disabled" do
      before { organization.disable_feature_flag!(:product_catalog) }

      it "rejects the request without creating a credit note" do
        expect { request }.not_to change(CreditNote, :count)

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the invoice belongs to another organization" do
      let(:invoice) { create(:invoice) }

      it "returns not found" do
        request

        expect(response).to be_not_found_error("invoice")
      end
    end
  end

  describe "POST /api/v2/credit_notes", :premium do
    subject(:request) do
      post_with_token(organization, "/api/v2/credit_notes", credit_note: {invoice_id: invoice.id, reason: "other", credit_amount_cents: 10, items: [{fee_id: fee.id, amount_cents: 10}]})
    end

    let(:fee) { create(:fee, invoice:, amount_cents: 100) }

    include_examples "requires API permission", "credit_note", "write"

    it "creates and returns a v2 credit note" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:credit_note]).to include(lago_invoice_id: invoice.id)
      expect(json[:credit_note]).not_to have_key(:coupons_adjustment_amount_cents)
    end

    context "when the product catalog is disabled" do
      before { organization.disable_feature_flag!(:product_catalog) }

      it "rejects the request without creating a credit note" do
        expect { request }.not_to change(CreditNote, :count)

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the invoice belongs to another organization" do
      let(:invoice) { create(:invoice) }

      it "returns not found" do
        request

        expect(response).to be_not_found_error("invoice")
      end
    end
  end

  describe "PUT /api/v2/credit_notes/:id" do
    subject(:request) { put_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}", credit_note: {refund_status: "succeeded"}) }

    include_examples "requires API permission", "credit_note", "write"

    it "returns the updated v2 payload" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
      expect(json[:credit_note]).not_to have_key(:precise_taxes_amount_cents)
    end
  end

  describe "PUT /api/v2/credit_notes/:id/void" do
    subject(:request) { put_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}/void") }

    include_examples "requires API permission", "credit_note", "write"

    it "returns the voided v2 payload" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:credit_note][:credit_status]).to eq("voided")
      expect(json[:credit_note]).not_to have_key(:taxes_rate)
    end
  end

  describe "POST /api/v2/credit_notes/:id/download_pdf" do
    subject(:request) { post_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}/download_pdf") }

    let(:credit_note) { create(:credit_note, :with_file, invoice:, customer:) }

    include_examples "requires API permission", "credit_note", "write"

    context "when the PDF exists" do
      it "returns the v2 payload" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:credit_note][:file_url]).to be_present
        expect(json[:credit_note]).not_to have_key(:precise_total_amount_cents)
      end
    end

    context "when only the XML exists" do
      let(:credit_note) { create(:credit_note, invoice:, customer:) }

      before do
        credit_note.xml_file.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.xml"))),
          filename: "credit_note.xml",
          content_type: "application/xml"
        )
      end

      it "generates the PDF instead of returning the XML", v2_timestamps: false do
        expect { request }.to have_enqueued_job(CreditNotes::GeneratePdfJob).with(credit_note)

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST /api/v2/credit_notes/:id/download_xml" do
    subject(:request) { post_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}/download_xml") }

    let(:credit_note) { create(:credit_note, invoice:, customer:) }

    context "when only the PDF exists" do
      let(:credit_note) { create(:credit_note, :with_file, invoice:, customer:) }

      it "generates the XML instead of returning the PDF", v2_timestamps: false do
        expect { request }.to have_enqueued_job(CreditNotes::GenerateXmlJob).with(credit_note)

        expect(response).to have_http_status(:ok)
      end
    end

    context "when the XML exists" do
      before do
        credit_note.xml_file.attach(
          io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.xml"))),
          filename: "credit_note.xml",
          content_type: "application/xml"
        )
      end

      it "returns the v2 payload" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
      end
    end
  end

  describe "POST /api/v2/credit_notes/:id/resend_email", :premium, v2_timestamps: false do
    subject(:request) do
      post_with_token(organization, "/api/v2/credit_notes/#{credit_note.id}/resend_email", recipients)
    end

    let(:customer) { create(:customer, organization:, email: "customer@example.com") }
    let(:invoice) { create(:invoice, organization:, customer:, status: :finalized) }
    let(:credit_note) { create(:credit_note, invoice:, customer:, status: :finalized) }
    let(:recipients) { {to: ["recipient@example.com"], cc: ["copy@example.com"], bcc: ["hidden@example.com"]} }

    include_examples "requires API permission", "credit_note", "write"

    it "enqueues the credit note email for the supplied recipients" do
      expect { request }.to have_enqueued_mail(CreditNoteMailer, :created).with(
        params: {
          credit_note:,
          resend: true,
          to: recipients[:to],
          cc: recipients[:cc],
          bcc: recipients[:bcc]
        },
        args: []
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
    end

    context "when the recipients are invalid" do
      let(:recipients) { {to: ["invalid"]} }

      it "returns a validation error without sending an email" do
        expect { request }.not_to have_enqueued_mail(CreditNoteMailer, :created)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details][:to]).to be_present
      end
    end

    context "when the credit note is a draft" do
      let(:credit_note) { create(:credit_note, :draft, invoice:, customer:) }

      it "returns not found without sending an email" do
        expect { request }.not_to have_enqueued_mail(CreditNoteMailer, :created)

        expect(response).to be_not_found_error("credit_note")
      end
    end

    context "when the credit note belongs to another organization" do
      let(:credit_note) { create(:credit_note, status: :finalized) }

      it "returns not found without sending an email" do
        expect { request }.not_to have_enqueued_mail(CreditNoteMailer, :created)

        expect(response).to be_not_found_error("credit_note")
      end
    end
  end

  describe "contract product-fee credit notes on v2", :premium do
    before { organization.enable_feature_flag!(:product_catalog) }

    let(:path) { "/api/v2/credit_notes" }
    let(:contract) { create(:contract, organization:, customer:) }
    let(:rate_card) { create(:rate_card, organization:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
    let(:invoice) do
      create(
        :invoice,
        organization:,
        customer:,
        status: invoice_status,
        payment_status: invoice_payment_status,
        currency: "EUR",
        fees_amount_cents: 100,
        total_amount_cents: 100,
        total_paid_amount_cents: 100
      )
    end
    let(:invoice_status) { "finalized" }
    let(:invoice_payment_status) { "succeeded" }
    let(:product_fee) do
      create(
        :product_fee,
        invoice:,
        subscription: nil,
        rate_card_rate:,
        contract:,
        contract_rate_card:,
        amount_cents: 100
      )
    end

    describe "POST /credit_notes" do
      subject do
        post_with_token(organization, path, credit_note: {
          invoice_id: invoice.id,
          reason: "other",
          credit_amount_cents: 50,
          items: [{fee_id: product_fee.id, amount_cents: item_amount_cents}]
        })
      end

      let(:item_amount_cents) { 50 }

      it "creates a credit note for the contract product fee and its source invoice" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_note][:lago_invoice_id]).to eq(invoice.id)
        get_with_token(organization, "#{path}/#{json[:credit_note][:lago_id]}", expands: ["items"])
        expect(json[:credit_note][:items]).to eq([{lago_fee_id: product_fee.id, amount_cents: 50}])
      end

      context "when the product catalog flag is disabled" do
        before { organization.disable_feature_flag!(:product_catalog) }

        it "rejects the request without creating a credit note" do
          expect { subject }.not_to change(CreditNote, :count)

          expect(response).to have_http_status(:forbidden)
        end
      end

      ["pending", "failed"].each do |status|
        context "when the source invoice status is #{status}" do
          let(:invoice_status) { status }

          it "returns an invalid type or status error without creating a credit note" do
            expect { subject }.not_to change(CreditNote, :count)

            expect(response).to have_http_status(:method_not_allowed)
            expect(json[:code]).to eq("invalid_type_or_status")
          end
        end
      end

      ["pending", "failed"].each do |payment_status|
        context "when a finalized invoice has payment status #{payment_status}" do
          let(:invoice_payment_status) { payment_status }

          it "creates the credit note" do
            subject
            expect(response).to have_http_status(:success)
          end
        end
      end

      context "when the item amount is malformed" do
        let(:item_amount_cents) { "bogus" }

        it "returns a validation error without creating a credit note" do
          expect { subject }.not_to change(CreditNote, :count)
          expect(response).to have_http_status(:unprocessable_content)
        end
      end

      context "when the item amount is a numeric string" do
        let(:item_amount_cents) { "50" }

        it "creates the credit note" do
          subject

          expect(response).to have_http_status(:success)
          get_with_token(organization, "#{path}/#{json[:credit_note][:lago_id]}", expands: ["items"])
          expect(json[:credit_note][:items].first[:amount_cents]).to eq(50)
        end
      end

      context "when the fee is not a member of the source invoice" do
        let(:other_invoice) { create(:invoice, organization:, customer:) }
        let(:product_fee) do
          create(
            :product_fee,
            invoice: other_invoice,
            subscription: nil,
            rate_card_rate:,
            contract:,
            contract_rate_card:,
            amount_cents: 100
          )
        end

        it "rejects the fee" do
          subject
          expect(response).not_to have_http_status(:success)
        end
      end

      context "when the source invoice belongs to another organization" do
        let(:foreign_invoice) { create(:invoice) }

        it "does not expose the foreign invoice" do
          post_with_token(organization, path, credit_note: {
            invoice_id: foreign_invoice.id,
            reason: "other",
            credit_amount_cents: 50,
            items: [{fee_id: product_fee.id, amount_cents: 50}]
          })

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    describe "POST /credit_notes/estimate" do
      subject do
        post_with_token(organization, "#{path}/estimate", credit_note: {
          invoice_id: invoice.id,
          items: [{fee_id: product_fee.id, amount_cents: item_amount_cents}]
        })
      end

      let(:item_amount_cents) { 50 }

      it "estimates the contract product fee against its source invoice" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:estimated_credit_note][:lago_invoice_id]).to eq(invoice.id)
        expect(json[:estimated_credit_note][:items].first[:amount_cents]).to eq(50)
      end

      context "when the product catalog flag is disabled" do
        before { organization.disable_feature_flag!(:product_catalog) }

        it "rejects the request" do
          expect { subject }.not_to change(CreditNote, :count)

          expect(response).to have_http_status(:forbidden)
        end
      end

      ["pending", "failed"].each do |status|
        context "when the source invoice status is #{status}" do
          let(:invoice_status) { status }

          it "returns an invalid type or status error without creating a credit note" do
            expect { subject }.not_to change(CreditNote, :count)

            expect(response).to have_http_status(:method_not_allowed)
            expect(json[:code]).to eq("invalid_type_or_status")
          end
        end
      end

      ["pending", "failed"].each do |payment_status|
        context "when a finalized invoice has payment status #{payment_status}" do
          let(:invoice_payment_status) { payment_status }

          it "returns the estimate" do
            subject
            expect(response).to have_http_status(:success)
          end
        end
      end

      context "when the item amount is malformed" do
        let(:item_amount_cents) { "bogus" }

        it "returns a validation error without creating a credit note" do
          expect { subject }.not_to change(CreditNote, :count)
          expect(response).to have_http_status(:unprocessable_content)
        end
      end

      context "when the item amount is a numeric string" do
        let(:item_amount_cents) { "50" }

        it "returns the estimate" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:estimated_credit_note][:items].first[:amount_cents]).to eq(50)
        end
      end

      context "when the fee belongs to another invoice" do
        let(:other_invoice) { create(:invoice, organization:, customer:) }
        let(:product_fee) do
          create(
            :product_fee,
            invoice: other_invoice,
            subscription: nil,
            rate_card_rate:,
            contract:,
            contract_rate_card:,
            amount_cents: 100
          )
        end

        it "rejects the fee" do
          subject
          expect(response).not_to have_http_status(:success)
        end
      end

      context "when the source invoice belongs to another organization" do
        let(:foreign_invoice) { create(:invoice) }

        it "does not expose the foreign invoice" do
          post_with_token(organization, "#{path}/estimate", credit_note: {
            invoice_id: foreign_invoice.id,
            items: [{fee_id: product_fee.id, amount_cents: 50}]
          })

          expect(response).to have_http_status(:not_found)
        end
      end
    end

    ["pdf", "xml"].each do |format|
      describe "POST /credit_notes/:id/download_#{format}" do
        subject do
          post_with_token(organization, "#{path}/#{credit_note.id}/download_#{format}")
        end

        let(:credit_note) { create(:credit_note, invoice:, customer:) }

        before do
          attachment = (format == "pdf") ? credit_note.file : credit_note.xml_file
          attachment.attach(
            io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.#{format}"))),
            filename: "blank.#{format}",
            content_type: (format == "pdf") ? "application/pdf" : "application/xml"
          )
          create(:credit_note_item, credit_note:, fee: product_fee) if credit_note.invoice_id == invoice.id
        end

        it "returns the existing credit note file response" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
        end

        context "when the credit note belongs to another organization" do
          let(:credit_note) { create(:credit_note) }

          it "returns not found" do
            subject
            expect(response).to have_http_status(:not_found)
          end
        end
      end
    end
  end
end
