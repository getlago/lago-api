# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::CreditNotesController, type: :request do
  let(:invoice) { create(:invoice) }
  let(:organization) { invoice.organization }
  let(:customer) { invoice.customer }
  let(:credit_note) { create(:credit_note, invoice: invoice, customer: customer) }
  let(:credit_note_items) { create_list(:credit_note_item, 2, credit_note: credit_note) }

  describe 'GET /credit_notes/:id' do
    before { credit_note_items }

    it 'returns a credit note' do
      get_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
        expect(json[:credit_note][:sequential_id]).to eq(credit_note.sequential_id)
        expect(json[:credit_note][:number]).to eq(credit_note.number)
        expect(json[:credit_note][:lago_invoice_id]).to eq(invoice.id)
        expect(json[:credit_note][:invoice_number]).to eq(invoice.number)
        expect(json[:credit_note][:status]).to eq(credit_note.status)
        expect(json[:credit_note][:reason]).to eq(credit_note.reason)
        expect(json[:credit_note][:amount_cents]).to eq(credit_note.amount_cents)
        expect(json[:credit_note][:amount_currency]).to eq(credit_note.amount_currency)
        expect(json[:credit_note][:remaining_amount_cents]).to eq(credit_note.remaining_amount_cents)
        expect(json[:credit_note][:remaining_amount_currency]).to eq(credit_note.remaining_amount_currency)
        expect(json[:credit_note][:created_at]).to eq(credit_note.created_at.iso8601)
        expect(json[:credit_note][:updated_at]).to eq(credit_note.updated_at.iso8601)

        expect(json[:credit_note][:items].count).to eq(2)

        json_item = json[:credit_note][:items].first
        item = credit_note_items.first
        expect(json_item[:lago_id]).to eq(item.id)
        expect(json_item[:credit_amount_cents]).to eq(item.credit_amount_cents)
        expect(json_item[:credit_amount_currency]).to eq(item.credit_amount_currency)
        expect(json_item[:fee][:lago_id]).to eq(item.fee.id)
        expect(json_item[:fee][:amount_cents]).to eq(item.fee.amount_cents)
        expect(json_item[:fee][:amount_currency]).to eq(item.fee.amount_currency)
        expect(json_item[:fee][:item][:type]).to eq(item.fee.fee_type)
        expect(json_item[:fee][:item][:code]).to eq(item.fee.item_code)
        expect(json_item[:fee][:item][:name]).to eq(item.fee.item_name)
      end
    end

    context 'when credit note does not exists' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/credit_notes/foo')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note belongs to another organization' do
      let(:wrong_credit_note) { create(:credit_note) }

      it 'returns not found' do
        get_with_token(organization, "/api/v1/credit_notes/#{wrong_credit_note.id}")
      end
    end
  end

  describe 'GET /credit_notes/:id/download' do
    it 'enqueues a job to generate the PDF' do
      post_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}/download")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(CreditNotes::GeneratePdfJob).to have_been_enqueued
      end
    end

    context 'when a file is attached to the credit note' do
      let(:credit_note) { create(:credit_note, :with_file, invoice: invoice, customer: customer) }

      it 'returns the credit note object' do
        post_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}/download")

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:credit_note]).to be_present
        end
      end
    end

    context 'when credit note does not exists' do
      it 'returns not found' do
        post_with_token(organization, '/api/v1/credit_notes/foo/download')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note belongs to another organization' do
      let(:wrong_credit_note) { create(:credit_note) }

      it 'returns not found' do
        post_with_token(organization, "/api/v1/credit_notes/#{wrong_credit_note.id}/download")
      end
    end
  end

  describe 'GET /credits_notes' do
    let(:second_customer) { create(:customer, organization: organization) }
    let(:second_invoice) { create(:invoice, customer: second_customer) }
    let(:second_credit_note) { create(:credit_note, invoice: second_invoice, customer: second_invoice.customer) }

    before do
      credit_note
      second_credit_note
    end

    it 'returns a list of credit_notes' do
      get_with_token(organization, '/api/v1/credit_notes')

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:credit_notes].count).to eq(2)
        expect(json[:credit_notes].first[:lago_id]).to eq(second_credit_note.id)
        expect(json[:credit_notes].last[:lago_id]).to eq(credit_note.id)
      end
    end

    context 'with pagination' do
      it 'returns the metadata' do
        get_with_token(organization, '/api/v1/credit_notes?page=1&per_page=1')

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:credit_notes].count).to eq(1)

          expect(json[:meta][:current_page]).to eq(1)
          expect(json[:meta][:next_page]).to eq(2)
          expect(json[:meta][:prev_page]).to eq(nil)
          expect(json[:meta][:total_pages]).to eq(2)
          expect(json[:meta][:total_count]).to eq(2)
        end
      end
    end

    context 'with external_customer_id filter' do
      it 'returns credit notes of the customer' do
        get_with_token(organization, "/api/v1/credit_notes?external_customer_id=#{customer.external_id}")

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:credit_notes].count).to eq(1)
          expect(json[:credit_notes].first[:lago_id]).to eq(credit_note.id)
        end
      end
    end
  end
end
