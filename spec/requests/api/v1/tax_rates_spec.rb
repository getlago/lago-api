# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::TaxRatesController, type: :request do
  let(:organization) { create(:organization) }

  describe 'POST /tax_rates' do
    let(:create_params) do
      {
        name: 'tax_rate',
        code: 'tax_rate_code',
        value: 20.0,
        description: 'tax_rate_description',
      }
    end

    it 'creates a tax rate' do
      expect { post_with_token(organization, '/api/v1/tax_rates', { tax_rate: create_params }) }
        .to change(TaxRate, :count).by(1)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax_rate][:lago_id]).to be_present
        expect(json[:tax_rate][:code]).to eq(create_params[:code])
        expect(json[:tax_rate][:name]).to eq(create_params[:name])
        expect(json[:tax_rate][:value]).to eq(create_params[:value])
        expect(json[:tax_rate][:description]).to eq(create_params[:description])
        expect(json[:tax_rate][:created_at]).to be_present
      end
    end
  end

  describe 'PUT /tax_rates/:code' do
    let(:tax_rate) { create(:tax_rate, organization:) }
    let(:code) { 'code_updated' }
    let(:name) { 'name_updated' }
    let(:value) { 15.0 }

    let(:update_params) do
      { code:, name:, value: }
    end

    it 'updates a tax rate' do
      put_with_token(
        organization,
        "/api/v1/tax_rates/#{tax_rate.code}",
        { tax_rate: update_params },
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax_rate][:lago_id]).to eq(tax_rate.id)
        expect(json[:tax_rate][:code]).to eq(update_params[:code])
        expect(json[:tax_rate][:name]).to eq(update_params[:name])
        expect(json[:tax_rate][:value]).to eq(update_params[:value])
      end
    end

    context 'when tax rate does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/tax_rates/unknown', { tax_rate: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when tax rate code already exists in organization scope (validation error)' do
      let(:tax_rate2) { create(:tax_rate, organization:) }
      let(:code) { tax_rate2.code }

      before { tax_rate2 }

      it 'returns unprocessable_entity error' do
        put_with_token(organization, "/api/v1/tax_rates/#{tax_rate.code}", { tax_rate: update_params })
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /tax_rates/:code' do
    let(:tax_rate) { create(:tax_rate, organization:) }

    it 'returns a tax rate' do
      get_with_token(organization, "/api/v1/tax_rates/#{tax_rate.code}")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax_rate][:lago_id]).to eq(tax_rate.id)
        expect(json[:tax_rate][:code]).to eq(tax_rate.code)
      end
    end

    context 'when tax rate does not exist' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/tax_rates/unknown')
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /tax_rates/:code' do
    let(:tax_rate) { create(:tax_rate, organization:) }

    before { tax_rate }

    it 'deletes a tax rate' do
      expect { delete_with_token(organization, "/api/v1/tax_rates/#{tax_rate.code}") }
        .to change(TaxRate, :count).by(-1)
    end

    it 'returns deleted tax rate' do
      delete_with_token(organization, "/api/v1/tax_rates/#{tax_rate.code}")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax_rate][:lago_id]).to eq(tax_rate.id)
        expect(json[:tax_rate][:code]).to eq(tax_rate.code)
      end
    end

    context 'when tax rate does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/tax_rates/unknown')
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /tax_rates' do
    let(:tax_rate) { create(:tax_rate, organization:) }

    before { tax_rate }

    it 'returns tax rates' do
      get_with_token(organization, '/api/v1/tax_rates')

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax_rates].count).to eq(1)
        expect(json[:tax_rates].first[:lago_id]).to eq(tax_rate.id)
        expect(json[:tax_rates].first[:code]).to eq(tax_rate.code)
      end
    end

    context 'with pagination' do
      let(:tax_rate2) { create(:tax_rate, organization:) }

      before { tax_rate2 }

      it 'returns tax rates with correct meta data' do
        get_with_token(organization, '/api/v1/tax_rates?page=1&per_page=1')

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:tax_rates].count).to eq(1)
          expect(json[:meta][:current_page]).to eq(1)
          expect(json[:meta][:next_page]).to eq(2)
          expect(json[:meta][:prev_page]).to eq(nil)
          expect(json[:meta][:total_pages]).to eq(2)
          expect(json[:meta][:total_count]).to eq(2)
        end
      end
    end
  end
end
