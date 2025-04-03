# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::CreditNotesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:credit_note) { create(:credit_note, invoice:, customer:) }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      payment_status: "succeeded",
      currency: "EUR",
      fees_amount_cents: 100,
      taxes_amount_cents: 120,
      total_amount_cents: 120
    )
  end

  describe "GET /api/v1/credit_notes/:id" do
    subject { get_with_token(organization, "/api/v1/credit_notes/#{credit_note_id}") }

    let(:credit_note_id) { credit_note.id }
    let!(:credit_note_items) { create_list(:credit_note_item, 2, credit_note:) }

    include_examples "requires API permission", "credit_note", "read"

    it "returns a credit note" do
      subject

      expect(response).to have_http_status(:success)

      expect(json[:credit_note]).to include(
        lago_id: credit_note.id,
        sequential_id: credit_note.sequential_id,
        number: credit_note.number,
        lago_invoice_id: invoice.id,
        invoice_number: invoice.number,
        credit_status: credit_note.credit_status,
        reason: credit_note.reason,
        currency: credit_note.currency,
        total_amount_cents: credit_note.total_amount_cents,
        credit_amount_cents: credit_note.credit_amount_cents,
        balance_amount_cents: credit_note.balance_amount_cents,
        created_at: credit_note.created_at.iso8601,
        updated_at: credit_note.updated_at.iso8601,
        applied_taxes: [],
        self_billed: invoice.self_billed
      )

      expect(json[:credit_note][:items].count).to eq(2)

      item = credit_note_items.first
      expect(json[:credit_note][:items][0]).to include(
        lago_id: item.id,
        amount_cents: item.amount_cents,
        amount_currency: item.amount_currency
      )

      expect(json[:credit_note][:items][0][:fee][:item]).to include(
        type: item.fee.fee_type,
        code: item.fee.item_code,
        name: item.fee.item_name
      )
    end

    context "when credit note does not exists" do
      let(:credit_note_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when credit note is draft" do
      let(:credit_note) { create(:credit_note, :draft) }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when credit note belongs to another organization" do
      let(:wrong_credit_note) { create(:credit_note) }
      let(:credit_note_id) { wrong_credit_note.id }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PUT /api/v1/credit_notes/:id" do
    subject do
      put_with_token(
        organization,
        "/api/v1/credit_notes/#{credit_note_id}",
        credit_note: update_params
      )
    end

    let(:credit_note_id) { credit_note.id }
    let(:update_params) { {refund_status: "succeeded"} }

    include_examples "requires API permission", "credit_note", "write"

    context "when credit not exists" do
      it "updates the credit note" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
        expect(json[:credit_note][:refund_status]).to eq("succeeded")
      end
    end

    context "when credit note does not exist" do
      let(:credit_note_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when provided refund status is invalid" do
      let(:update_params) { {refund_status: "invalid_status"} }

      it "returns an unprocessable entity error" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /api/v1/credit_notes/:id/download" do
    subject do
      post_with_token(organization, "/api/v1/credit_notes/#{credit_note_id}/download")
    end

    let(:credit_note_id) { credit_note.id }

    include_examples "requires API permission", "credit_note", "write"

    it "enqueues a job to generate the PDF" do
      subject

      expect(response).to have_http_status(:success)
      expect(CreditNotes::GeneratePdfJob).to have_been_enqueued
    end

    context "when a file is attached to the credit note" do
      let(:credit_note) { create(:credit_note, :with_file, invoice:, customer:) }

      it "returns the credit note object" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_note]).to be_present
      end
    end

    context "when credit note does not exist" do
      let(:credit_note_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when credit note is draft" do
      let(:credit_note) { create(:credit_note, :draft) }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when credit note belongs to another organization" do
      let(:wrong_credit_note) { create(:credit_note) }
      let(:credit_note_id) { wrong_credit_note.id }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/credit_notes" do
    subject { get_with_token(organization, "/api/v1/credit_notes", params) }

    let(:organization) { customer.organization }
    let(:customer) { create(:customer) }

    context "with no params" do
      let(:params) { {} }
      let(:invoices) { create_pair(:invoice, organization:, customer:) }

      let!(:credit_notes) do
        invoices.map { |invoice| create(:credit_note, invoice:, customer:) }
      end

      include_examples "requires API permission", "credit_note", "read"

      it "returns a list of credit notes" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].first[:items]).to be_empty
        expect(json[:credit_notes].pluck(:lago_id)).to match_array credit_notes.pluck(:id)
      end
    end

    context "with pagination" do
      let(:params) { {page: 1, per_page: 1} }
      let(:invoices) { create_pair(:invoice, organization:, customer:) }

      before do
        invoices.map { |invoice| create(:credit_note, invoice:, customer:) }
      end

      it "returns the metadata" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].count).to eq(1)

        expect(json[:meta]).to include(
          current_page: 1,
          next_page: 2,
          prev_page: nil,
          total_pages: 2,
          total_count: 2
        )
      end
    end

    context "with external_customer_id filter" do
      let(:params) { {external_customer_id: customer.external_id} }
      let!(:credit_note) { create(:credit_note, customer:) }

      before do
        another_customer = create(:customer, organization:)
        create(:credit_note, customer: another_customer)
      end

      it "returns credit notes of the customer" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to contain_exactly credit_note.id
      end
    end

    context "with reason filter" do
      let(:params) { {reason: matching_reasons} }
      let(:matching_reasons) { CreditNote::REASON.sample(2) }

      let!(:matching_credit_notes) do
        matching_reasons.map { |reason| create(:credit_note, reason:, customer:) }
      end

      before do
        create(
          :credit_note,
          reason: CreditNote::REASON.excluding(matching_reasons).sample,
          customer:
        )
      end

      it "returns credit notes with matching reasons" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to match_array matching_credit_notes.pluck(:id)
      end
    end

    context "with credit status filter" do
      let(:params) { {credit_status: matching_credit_statuses} }
      let(:matching_credit_statuses) { CreditNote::CREDIT_STATUS.sample(2) }

      let!(:matching_credit_notes) do
        matching_credit_statuses.map do |credit_status|
          create(:credit_note, credit_status:, customer:)
        end
      end

      before do
        create(
          :credit_note,
          credit_status: CreditNote::CREDIT_STATUS.excluding(matching_credit_statuses).sample,
          customer:
        )
      end

      it "returns credit notes with matching credit statuses" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to match_array matching_credit_notes.pluck(:id)
      end
    end

    context "with refund status filter" do
      let(:params) { {refund_status: matching_refund_statuses} }
      let(:matching_refund_statuses) { CreditNote::REFUND_STATUS.sample(2) }

      let!(:matching_credit_notes) do
        matching_refund_statuses.map do |refund_status|
          create(:credit_note, refund_status:, customer:)
        end
      end

      before do
        create(
          :credit_note,
          refund_status: CreditNote::REFUND_STATUS.excluding(matching_refund_statuses).sample,
          customer:
        )
      end

      it "returns credit notes with matching refund statuses" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to match_array matching_credit_notes.pluck(:id)
      end
    end

    context "with invoice number filter" do
      let(:params) { {invoice_number: matching_credit_note.invoice.number} }
      let!(:matching_credit_note) { create(:credit_note, customer:) }

      before { create(:credit_note, customer:) }

      it "returns credit notes with matching invoice number" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to contain_exactly matching_credit_note.id
      end
    end

    context "with issuing date filters" do
      let(:params) do
        {
          issuing_date_from: credit_notes.second.issuing_date,
          issuing_date_to: credit_notes.fourth.issuing_date
        }
      end

      let!(:credit_notes) do
        (1..5).to_a.map do |i|
          create(:credit_note, issuing_date: i.days.ago, customer:)
        end.reverse # from oldest to newest
      end

      it "returns credit notes that were issued between provided dates" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to match_array credit_notes[1..3].pluck(:id)
      end
    end

    context "with amount filters" do
      let(:params) do
        {
          amount_from: credit_notes.second.total_amount_cents,
          amount_to: credit_notes.fourth.total_amount_cents
        }
      end

      let!(:credit_notes) do
        (1..5).to_a.map do |i|
          create(:credit_note, total_amount_cents: i.succ * 1_000, customer:)
        end # from smallest to biggest
      end

      it "returns credit notes with total cents amount in provided range" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to match_array credit_notes[1..3].pluck(:id)
      end
    end

    context "with self billed invoice filter" do
      let(:params) { {self_billed: true} }

      let(:self_billed_credit_note) do
        invoice = create(:invoice, :self_billed, customer:, organization:)

        create(:credit_note, invoice:, customer:)
      end

      let(:non_self_billed_credit_note) do
        create(:credit_note, customer:)
      end

      before do
        self_billed_credit_note
        non_self_billed_credit_note
      end

      it "returns self billed credit_notes" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].count).to eq(1)
        expect(json[:credit_notes].first[:lago_id]).to eq(self_billed_credit_note.id)
      end

      context "when self billed is false" do
        let(:params) { {self_billed: false} }

        it "returns non self billed credit_notes" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:credit_notes].count).to eq(1)
          expect(json[:credit_notes].first[:lago_id]).to eq(non_self_billed_credit_note.id)
        end
      end

      context "when self billed is nil" do
        let(:params) { {self_billed: nil} }

        it "returns all credit_notes" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:credit_notes].count).to eq(2)
        end
      end
    end

    context "with search term" do
      let(:params) { {search_term: matching_credit_note.invoice.number} }
      let!(:matching_credit_note) { create(:credit_note, customer:) }

      before { create(:credit_note, customer:) }

      it "returns credit notes matching the search terms" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to contain_exactly matching_credit_note.id
      end
    end

    context "with billing entity codes filter" do
      let(:params) { {billing_entity_codes: [billing_entity.code]} }
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:matching_credit_note) { create(:credit_note, customer:, invoice: create(:invoice, billing_entity:)) }
      let(:other_credit_note) { create(:credit_note, customer:) }

      before do
        matching_credit_note
        other_credit_note
      end

      it "returns credit notes with matching billing entity code" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].pluck(:lago_id)).to contain_exactly matching_credit_note.id
      end

      context "when billing entity code is not found" do
        let(:params) { {billing_entity_codes: [SecureRandom.uuid]} }

        it "returns an error" do
          subject

          expect(response).to have_http_status(:not_found)
          expect(json[:code]).to eq("billing_entity_not_found")
        end
      end
    end
  end

  describe "POST /api/v1/credit_notes" do
    subject do
      post_with_token(organization, "/api/v1/credit_notes", {credit_note: create_params})
    end

    let(:fee1) { create(:fee, invoice:) }
    let(:fee2) { create(:charge_fee, invoice:) }
    let(:invoice_id) { invoice.id }

    let(:create_params) do
      {
        invoice_id:,
        reason: "duplicated_charge",
        description: "Duplicated charge",
        credit_amount_cents: 10,
        refund_amount_cents: 5,
        items: [
          {
            fee_id: fee1.id,
            amount_cents: 10
          },
          {
            fee_id: fee2.id,
            amount_cents: 5
          }
        ]
      }
    end

    around { |test| lago_premium!(&test) }

    include_examples "requires API permission", "credit_note", "write"

    it "creates a credit note" do
      subject

      expect(response).to have_http_status(:success)

      expect(json[:credit_note]).to include(
        credit_status: "available",
        refund_status: "pending",
        reason: "duplicated_charge",
        description: "Duplicated charge",
        currency: "EUR",
        total_amount_cents: 15,
        credit_amount_cents: 10,
        balance_amount_cents: 10,
        refund_amount_cents: 5,
        applied_taxes: []
      )

      expect(json[:credit_note][:items][0][:lago_id]).to be_present
      expect(json[:credit_note][:items][0][:amount_cents]).to eq(10)
      expect(json[:credit_note][:items][0][:amount_currency]).to eq("EUR")
      expect(json[:credit_note][:items][0][:fee][:lago_id]).to eq(fee1.id)

      expect(json[:credit_note][:items][1][:lago_id]).to be_present
      expect(json[:credit_note][:items][1][:amount_cents]).to eq(5)
      expect(json[:credit_note][:items][1][:amount_currency]).to eq("EUR")
      expect(json[:credit_note][:items][1][:fee][:lago_id]).to eq(fee2.id)
    end

    context "when invoice is not found" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PUT /api/v1/credit_notes/:id/void" do
    subject { put_with_token(organization, "/api/v1/credit_notes/#{credit_note_id}/void") }

    let(:credit_note_id) { credit_note.id }

    include_examples "requires API permission", "credit_note", "write"

    it "voids the credit note" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
      expect(json[:credit_note][:credit_status]).to eq("voided")
      expect(json[:credit_note][:balance_amount_cents]).to eq(0)
    end

    context "when credit note does not exist" do
      let(:credit_note_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when credit note is not voidable" do
      before { credit_note.update!(credit_amount_cents: 0, credit_status: :voided) }

      it "returns an unprocessable entity error" do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end

  describe "POST /api/v1/credit_notes/estimate" do
    subject do
      post_with_token(
        organization,
        "/api/v1/credit_notes/estimate",
        {credit_note: estimate_params}
      )
    end

    let(:fees) { create_list(:fee, 2, invoice:, amount_cents: 100) }
    let(:invoice_id) { invoice.id }

    let(:estimate_params) do
      {
        invoice_id:,
        items: fees.map { |f| {fee_id: f.id, amount_cents: 50} }
      }
    end

    around { |test| lago_premium!(&test) }

    include_examples "requires API permission", "credit_note", "write"

    it "returns the computed amounts for credit note creation" do
      subject

      expect(response).to have_http_status(:success)

      estimated_credit_note = json[:estimated_credit_note]
      expect(estimated_credit_note[:lago_invoice_id]).to eq(invoice.id)
      expect(estimated_credit_note[:invoice_number]).to eq(invoice.number)
      expect(estimated_credit_note[:currency]).to eq("EUR")
      expect(estimated_credit_note[:taxes_amount_cents]).to eq(0)
      expect(estimated_credit_note[:sub_total_excluding_taxes_amount_cents]).to eq(100)
      expect(estimated_credit_note[:max_creditable_amount_cents]).to eq(100)
      expect(estimated_credit_note[:max_refundable_amount_cents]).to eq(0)
      expect(estimated_credit_note[:coupons_adjustment_amount_cents]).to eq(0)
      expect(estimated_credit_note[:items].first[:amount_cents]).to eq(50)
      expect(estimated_credit_note[:applied_taxes]).to be_blank
    end

    context "with invalid invoice" do
      let(:invoice) { create(:invoice) }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
