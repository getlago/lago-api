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

        expect(json[:fee][:lago_id]).to eq(fee.id)
        expect(json[:fee][:lago_group_id]).to eq(fee.group_id)
        expect(json[:fee][:item][:type]).to eq(fee.fee_type)
        expect(json[:fee][:item][:code]).to eq(fee.item_code)
        expect(json[:fee][:item][:name]).to eq(fee.item_name)
        expect(json[:fee][:amount_cents]).to eq(fee.amount_cents)
        expect(json[:fee][:amount_currency]).to eq(fee.amount_currency)
        expect(json[:fee][:vat_amount_cents]).to eq(fee.vat_amount_cents)
        expect(json[:fee][:vat_amount_currency]).to eq(fee.vat_amount_currency)
        expect(json[:fee][:units]).to eq(fee.units.to_s)
        expect(json[:fee][:events_count]).to eq(fee.events_count)
      end
    end

    context 'when fee is an add-on fee' do
      let(:invoice) { create(:invoice, organization:) }
      let(:fee) { create(:add_on_fee, invoice:) }

      it 'returns a fee' do
        get_with_token(organization, "/api/v1/fees/#{fee.id}")

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:fee][:lago_id]).to eq(fee.id)
          expect(json[:fee][:lago_group_id]).to eq(fee.group_id)
          expect(json[:fee][:item][:type]).to eq(fee.fee_type)
          expect(json[:fee][:item][:code]).to eq(fee.item_code)
          expect(json[:fee][:item][:name]).to eq(fee.item_name)
          expect(json[:fee][:amount_cents]).to eq(fee.amount_cents)
          expect(json[:fee][:amount_currency]).to eq(fee.amount_currency)
          expect(json[:fee][:vat_amount_cents]).to eq(fee.vat_amount_cents)
          expect(json[:fee][:vat_amount_currency]).to eq(fee.vat_amount_currency)
          expect(json[:fee][:units]).to eq(fee.units.to_s)
          expect(json[:fee][:events_count]).to eq(fee.events_count)
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
end
