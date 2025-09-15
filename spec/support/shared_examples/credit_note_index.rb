# frozen_string_literal: true

RSpec.shared_examples "a credit note index endpoint" do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:params) { {} }

  context "with no params" do
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

    before do
      invoice = create(:invoice, customer:, number: "FOO-01")
      create(:credit_note, customer:, invoice:)
    end

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

    before do
      invoice = create(:invoice, customer:, number: "FOO-01")
      create(:credit_note, customer:, invoice:)
    end

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

    context "when one of billing entity codes is not found" do
      let(:params) { {billing_entity_codes: [billing_entity.code, SecureRandom.uuid]} }

      it "returns an error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("billing_entity_not_found")
      end
    end
  end
end
