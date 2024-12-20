# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::CreditNotesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:credit_note) { create(:credit_note, invoice:, customer:) }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      payment_status: 'succeeded',
      currency: 'EUR',
      fees_amount_cents: 100,
      taxes_amount_cents: 120,
      total_amount_cents: 120
    )
  end

  describe 'GET /api/v1/credit_notes/:id' do
    subject { get_with_token(organization, "/api/v1/credit_notes/#{credit_note_id}") }

    let(:credit_note_id) { credit_note.id }
    let!(:credit_note_items) { create_list(:credit_note_item, 2, credit_note:) }

    include_examples 'requires API permission', 'credit_note', 'read'

    it 'returns a credit note' do
      subject

      aggregate_failures do
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
          applied_taxes: []
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
    end

    context 'when credit note does not exists' do
      let(:credit_note_id) { SecureRandom.uuid }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note is draft' do
      let(:credit_note) { create(:credit_note, :draft) }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note belongs to another organization' do
      let(:wrong_credit_note) { create(:credit_note) }
      let(:credit_note_id) { wrong_credit_note.id }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /api/v1/credit_notes/:id' do
    subject do
      put_with_token(
        organization,
        "/api/v1/credit_notes/#{credit_note_id}",
        credit_note: update_params
      )
    end

    let(:credit_note_id) { credit_note.id }
    let(:update_params) { {refund_status: 'succeeded'} }

    include_examples 'requires API permission', 'credit_note', 'write'

    context 'when credit not exists' do
      it 'updates the credit note' do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
          expect(json[:credit_note][:refund_status]).to eq('succeeded')
        end
      end
    end

    context 'when credit note does not exist' do
      let(:credit_note_id) { SecureRandom.uuid }

      it 'returns a not found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when provided refund status is invalid' do
      let(:update_params) { {refund_status: 'invalid_status'} }

      it 'returns an unprocessable entity error' do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/credit_notes/:id/download' do
    subject do
      post_with_token(organization, "/api/v1/credit_notes/#{credit_note_id}/download")
    end

    let(:credit_note_id) { credit_note.id }

    include_examples 'requires API permission', 'credit_note', 'write'

    it 'enqueues a job to generate the PDF' do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(CreditNotes::GeneratePdfJob).to have_been_enqueued
      end
    end

    context 'when a file is attached to the credit note' do
      let(:credit_note) { create(:credit_note, :with_file, invoice:, customer:) }

      it 'returns the credit note object' do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:credit_note]).to be_present
        end
      end
    end

    context 'when credit note does not exist' do
      let(:credit_note_id) { SecureRandom.uuid }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note is draft' do
      let(:credit_note) { create(:credit_note, :draft) }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note belongs to another organization' do
      let(:wrong_credit_note) { create(:credit_note) }
      let(:credit_note_id) { wrong_credit_note.id }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/credit_notes' do
    subject { get_with_token(organization, '/api/v1/credit_notes', params) }

    let(:second_customer) { create(:customer, organization:) }
    let(:second_invoice) { create(:invoice, customer: second_customer, organization:) }
    let(:params) { {} }

    let(:another_customer_credit_note) do
      create(:credit_note, invoice: second_invoice, customer: second_invoice.customer)
    end

    let!(:credit_note_ids) do
      [
        credit_note,
        another_customer_credit_note
      ].pluck(:id)
    end

    include_examples 'requires API permission', 'credit_note', 'read'

    it 'returns a list of credit_notes' do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].count).to eq(2)
        expect(json[:credit_notes].first[:items]).to be_empty
        expect(json[:credit_notes].map { |i| i[:lago_id] }).to match_array credit_note_ids
      end
    end

    context 'with pagination' do
      let(:params) { {page: 1, per_page: 1} }

      it 'returns the metadata' do
        subject

        aggregate_failures do
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
    end

    context 'with external_customer_id filter' do
      let(:params) { {external_customer_id: customer.external_id} }

      it 'returns credit notes of the customer' do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:credit_notes].count).to eq(1)
          expect(json[:credit_notes].first[:lago_id]).to eq(credit_note.id)
        end
      end
    end
  end

  describe 'POST /api/v1/credit_notes' do
    subject do
      post_with_token(organization, '/api/v1/credit_notes', {credit_note: create_params})
    end

    let(:fee1) { create(:fee, invoice:) }
    let(:fee2) { create(:charge_fee, invoice:) }
    let(:invoice_id) { invoice.id }

    let(:create_params) do
      {
        invoice_id:,
        reason: 'duplicated_charge',
        description: 'Duplicated charge',
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

    include_examples 'requires API permission', 'credit_note', 'write'

    it 'creates a credit note' do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:credit_note]).to include(
          credit_status: 'available',
          refund_status: 'pending',
          reason: 'duplicated_charge',
          description: 'Duplicated charge',
          currency: 'EUR',
          total_amount_cents: 15,
          credit_amount_cents: 10,
          balance_amount_cents: 10,
          refund_amount_cents: 5,
          applied_taxes: []
        )

        expect(json[:credit_note][:items][0][:lago_id]).to be_present
        expect(json[:credit_note][:items][0][:amount_cents]).to eq(10)
        expect(json[:credit_note][:items][0][:amount_currency]).to eq('EUR')
        expect(json[:credit_note][:items][0][:fee][:lago_id]).to eq(fee1.id)

        expect(json[:credit_note][:items][1][:lago_id]).to be_present
        expect(json[:credit_note][:items][1][:amount_cents]).to eq(5)
        expect(json[:credit_note][:items][1][:amount_currency]).to eq('EUR')
        expect(json[:credit_note][:items][1][:fee][:lago_id]).to eq(fee2.id)
      end
    end

    context 'when invoice is not found' do
      let(:invoice_id) { SecureRandom.uuid }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /api/v1/credit_notes/:id/void' do
    subject { put_with_token(organization, "/api/v1/credit_notes/#{credit_note_id}/void") }

    let(:credit_note_id) { credit_note.id }

    include_examples 'requires API permission', 'credit_note', 'write'

    it 'voids the credit note' do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
        expect(json[:credit_note][:credit_status]).to eq('voided')
        expect(json[:credit_note][:balance_amount_cents]).to eq(0)
      end
    end

    context 'when credit note does not exist' do
      let(:credit_note_id) { SecureRandom.uuid }

      it 'returns a not found error' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note is not voidable' do
      before { credit_note.update!(credit_amount_cents: 0, credit_status: :voided) }

      it 'returns an unprocessable entity error' do
        subject
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end

  describe 'POST /api/v1/credit_notes/estimate' do
    subject do
      post_with_token(
        organization,
        '/api/v1/credit_notes/estimate',
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

    include_examples 'requires API permission', 'credit_note', 'write'

    it 'returns the computed amounts for credit note creation' do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)

        estimated_credit_note = json[:estimated_credit_note]
        expect(estimated_credit_note[:lago_invoice_id]).to eq(invoice.id)
        expect(estimated_credit_note[:invoice_number]).to eq(invoice.number)
        expect(estimated_credit_note[:currency]).to eq('EUR')
        expect(estimated_credit_note[:taxes_amount_cents]).to eq(0)
        expect(estimated_credit_note[:sub_total_excluding_taxes_amount_cents]).to eq(100)
        expect(estimated_credit_note[:max_creditable_amount_cents]).to eq(100)
        expect(estimated_credit_note[:max_refundable_amount_cents]).to eq(100)
        expect(estimated_credit_note[:coupons_adjustment_amount_cents]).to eq(0)
        expect(estimated_credit_note[:items].first[:amount_cents]).to eq(50)
        expect(estimated_credit_note[:applied_taxes]).to be_blank
      end
    end

    context 'with invalid invoice' do
      let(:invoice) { create(:invoice) }

      it 'returns not found' do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
