# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::FeesController, type: :request do
  let(:organization) { create(:organization) }

  describe 'GET /fees/:id' do
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:) }
    let(:fee) { create(:fee, subscription:, invoice: nil) }

    it 'returns a fee' do
      get_with_token(organization, "/api/v1/fees/#{fee.id}")

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:fee]).to include(
          lago_id: fee.id,
          amount_cents: fee.amount_cents,
          amount_currency: fee.amount_currency,
          taxes_amount_cents: fee.taxes_amount_cents,
          units: fee.units.to_s,
          events_count: fee.events_count,
          applied_taxes: []
        )
        expect(json[:fee][:item]).to include(
          type: fee.fee_type,
          code: fee.item_code,
          name: fee.item_name
        )
      end
    end

    context 'when fee is an add-on fee' do
      let(:invoice) { create(:invoice, organization:) }
      let(:fee) { create(:add_on_fee, invoice:) }

      it 'returns a fee' do
        get_with_token(organization, "/api/v1/fees/#{fee.id}")

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:fee]).to include(
            lago_id: fee.id,
            amount_cents: fee.amount_cents,
            amount_currency: fee.amount_currency,
            taxes_amount_cents: fee.taxes_amount_cents,
            units: fee.units.to_s,
            events_count: fee.events_count,
            applied_taxes: []
          )
          expect(json[:fee][:item]).to include(
            type: fee.fee_type,
            code: fee.item_code,
            name: fee.item_name
          )
        end
      end
    end

    context 'when fee does not exsits' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/fees/foo')

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when fee belongs to an other organization' do
      let(:fee) { create(:fee) }

      it 'returns not found' do
        get_with_token(organization, "/api/v1/fee/#{fee.id}")

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /fees/:id' do
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:) }
    let(:update_params) { {payment_status: 'succeeded'} }
    let(:fee) do
      create(:charge_fee, fee_type: 'charge', pay_in_advance: true, subscription:, invoice: nil)
    end

    before { fee.charge.update!(invoiceable: false) }

    it 'updates the fee' do
      put_with_token(organization, "/api/v1/fees/#{fee.id}", fee: update_params)

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:fee]).to include(
          lago_id: fee.reload.id,
          amount_cents: fee.amount_cents,
          amount_currency: fee.amount_currency,
          taxes_amount_cents: fee.taxes_amount_cents,
          units: fee.units.to_s,
          events_count: fee.events_count,
          payment_status: fee.payment_status,
          created_at: fee.created_at&.iso8601,
          succeeded_at: fee.succeeded_at&.iso8601,
          failed_at: fee.failed_at&.iso8601,
          refunded_at: fee.refunded_at&.iso8601,
          amount_details: fee.amount_details,
          applied_taxes: []
        )
        expect(json[:fee][:item]).to include(
          type: fee.fee_type,
          code: fee.item_code,
          name: fee.item_name
        )
      end
    end

    context 'when fee does not exist' do
      it 'returns not found' do
        put_with_token(organization, '/api/v1/fees/foo', fee: update_params)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /fees/:id' do
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:) }
    let(:update_params) { {payment_status: 'succeeded'} }
    let(:fee) do
      create(:charge_fee, fee_type: 'charge', pay_in_advance: true, subscription:, invoice: nil)
    end

    context 'when fee exist' do
      it 'deletes the fee' do
        delete_with_token(organization, "/api/v1/fees/#{fee.id}")
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when fee exist but is attached to an invoice' do
      let(:invoice) { create(:invoice, organization:, customer:) }
      let(:fee) do
        create(:charge_fee, fee_type: 'charge', pay_in_advance: true, subscription:, invoice:)
      end

      it 'dont delete the fee' do
        delete_with_token(organization, "/api/v1/fees/#{fee.id}")
        expect(response).to have_http_status(:method_not_allowed)
      end
    end
  end

  describe 'GET /fees' do
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, customer:) }
    let(:fee) { create(:fee, subscription:, invoice: nil) }

    before { fee }

    it 'returns a list of fees' do
      get_with_token(organization, '/api/v1/fees')

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:fees].count).to eq(1)
      end
    end

    context 'with an invalid filter' do
      it 'returns an error response' do
        get_with_token(organization, '/api/v1/fees', fee_type: 'foo_bar')

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details]).to eq({fee_type: %w[value_is_invalid]})
        end
      end
    end
  end
end
