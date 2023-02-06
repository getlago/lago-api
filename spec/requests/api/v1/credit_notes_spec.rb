# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::CreditNotesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:credit_note) { create(:credit_note, invoice:, customer:) }
  let(:credit_note_items) { create_list(:credit_note_item, 2, credit_note:) }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      payment_status: 'succeeded',
      amount_cents: 100,
      amount_currency: 'EUR',
      vat_amount_cents: 120,
      vat_amount_currency: 'EUR',
      total_amount_cents: 120,
      total_amount_currency: 'EUR',
    )
  end

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
        expect(json[:credit_note][:credit_status]).to eq(credit_note.credit_status)
        expect(json[:credit_note][:reason]).to eq(credit_note.reason)
        expect(json[:credit_note][:total_amount_cents]).to eq(credit_note.total_amount_cents)
        expect(json[:credit_note][:total_amount_currency]).to eq(credit_note.total_amount_currency)
        expect(json[:credit_note][:credit_amount_cents]).to eq(credit_note.credit_amount_cents)
        expect(json[:credit_note][:credit_amount_currency]).to eq(credit_note.credit_amount_currency)
        expect(json[:credit_note][:balance_amount_cents]).to eq(credit_note.balance_amount_cents)
        expect(json[:credit_note][:balance_amount_currency]).to eq(credit_note.balance_amount_currency)
        expect(json[:credit_note][:created_at]).to eq(credit_note.created_at.iso8601)
        expect(json[:credit_note][:updated_at]).to eq(credit_note.updated_at.iso8601)

        expect(json[:credit_note][:items].count).to eq(2)

        json_item = json[:credit_note][:items].first
        item = credit_note_items.first
        expect(json_item[:lago_id]).to eq(item.id)
        expect(json_item[:amount_cents]).to eq(item.amount_cents)
        expect(json_item[:amount_currency]).to eq(item.amount_currency)
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

    context 'when credit note is draft' do
      let(:credit_note) { create(:credit_note, :draft) }

      it 'returns not found' do
        get_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}")

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note belongs to another organization' do
      let(:wrong_credit_note) { create(:credit_note) }

      it 'returns not found' do
        get_with_token(organization, "/api/v1/credit_notes/#{wrong_credit_note.id}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /credit_notes/:id' do
    let(:update_params) { { refund_status: 'succeeded' } }

    it 'updates the credit note' do
      put_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}", credit_note: update_params)

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
        expect(json[:credit_note][:refund_status]).to eq('succeeded')
      end
    end

    context 'when credit note does not exist' do
      it 'returns a not found error' do
        put_with_token(organization, '/api/v1/credit_notes/555', credit_note: update_params)

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when provided refund status is invalid' do
      let(:update_params) { { refund_status: 'foo_bar' } }

      it 'returns an unprocessable entity error' do
        put_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}", credit_note: update_params)

        expect(response).to have_http_status(:unprocessable_entity)
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
      let(:credit_note) { create(:credit_note, :with_file, invoice:, customer:) }

      it 'returns the credit note object' do
        post_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}/download")

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:credit_note]).to be_present
        end
      end
    end

    context 'when credit note does not exist' do
      it 'returns not found' do
        post_with_token(organization, '/api/v1/credit_notes/foo/download')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note is draft' do
      let(:credit_note) { create(:credit_note, :draft) }

      it 'returns not found' do
        post_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}/download")

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note belongs to another organization' do
      let(:wrong_credit_note) { create(:credit_note) }

      it 'returns not found' do
        post_with_token(organization, "/api/v1/credit_notes/#{wrong_credit_note.id}/download")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /credit_notes' do
    let(:second_customer) { create(:customer, organization:) }
    let(:second_invoice) { create(:invoice, customer: second_customer, organization:) }
    let(:second_credit_note) { create(:credit_note, invoice: second_invoice, customer: second_invoice.customer) }
    let(:draft_credit_note) { create(:credit_note, :draft, customer: second_customer) }

    before do
      credit_note
      second_credit_note
      draft_credit_note
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

  describe 'POST /credit_notes' do
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
            amount_cents: 10,
          },
          {
            fee_id: fee2.id,
            amount_cents: 5,
          },
        ],
      }
    end

    around { |test| lago_premium!(&test) }

    it 'creates a credit note' do
      post_with_token(organization, '/api/v1/credit_notes', { credit_note: create_params })

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:credit_note][:lago_id]).to be_present
        expect(json[:credit_note][:credit_status]).to eq('available')
        expect(json[:credit_note][:refund_status]).to eq('pending')
        expect(json[:credit_note][:reason]).to eq('duplicated_charge')
        expect(json[:credit_note][:description]).to eq('Duplicated charge')
        expect(json[:credit_note][:total_amount_cents]).to eq(15)
        expect(json[:credit_note][:total_amount_currency]).to eq('EUR')
        expect(json[:credit_note][:credit_amount_cents]).to eq(10)
        expect(json[:credit_note][:credit_amount_currency]).to eq('EUR')
        expect(json[:credit_note][:balance_amount_cents]).to eq(10)
        expect(json[:credit_note][:balance_amount_currency]).to eq('EUR')
        expect(json[:credit_note][:refund_amount_cents]).to eq(5)
        expect(json[:credit_note][:refund_amount_currency]).to eq('EUR')

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
      let(:invoice_id) { 'foo_id' }

      it 'returns not found' do
        post_with_token(organization, '/api/v1/credit_notes', { credit_note: create_params })

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /credit_notes/:id/void' do
    it 'voids the credit note' do
      put_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}/void")

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:credit_note][:lago_id]).to eq(credit_note.id)
        expect(json[:credit_note][:credit_status]).to eq('voided')
        expect(json[:credit_note][:balance_amount_cents]).to eq(0)
      end
    end

    context 'when credit note does not exist' do
      it 'returns a not found error' do
        put_with_token(organization, '/api/v1/credit_notes/555/void')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when credit note is not voidable' do
      before { credit_note.update!(credit_amount_cents: 0, credit_status: :voided) }

      it 'returns an unprocessable entity error' do
        put_with_token(organization, "/api/v1/credit_notes/#{credit_note.id}/void")

        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end
end
