# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::TaxesController, type: :request do
  let(:organization) { create(:organization) }

  describe 'POST /taxes' do
    let(:create_params) do
      {
        name: 'tax',
        code: 'tax_code',
        rate: 20.0,
        description: 'tax_description',
        applied_to_organization: false,
      }
    end

    it 'creates a tax' do
      expect { post_with_token(organization, '/api/v1/taxes', {tax: create_params}) }
        .to change(Tax, :count).by(1)

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax][:lago_id]).to be_present
        expect(json[:tax][:code]).to eq(create_params[:code])
        expect(json[:tax][:name]).to eq(create_params[:name])
        expect(json[:tax][:rate]).to eq(create_params[:rate])
        expect(json[:tax][:description]).to eq(create_params[:description])
        expect(json[:tax][:created_at]).to be_present
        expect(json[:tax][:applied_to_organization]).to eq(create_params[:applied_to_organization])
      end
    end
  end

  describe 'PUT /taxes/:code' do
    let(:tax) { create(:tax, organization:) }
    let(:code) { 'code_updated' }
    let(:name) { 'name_updated' }
    let(:rate) { 15.0 }
    let(:applied_to_organization) { false }

    let(:update_params) do
      {code:, name:, rate:, applied_to_organization:}
    end

    it 'updates a tax' do
      put_with_token(
        organization,
        "/api/v1/taxes/#{tax.code}",
        {tax: update_params},
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax][:lago_id]).to eq(tax.id)
        expect(json[:tax][:code]).to eq(update_params[:code])
        expect(json[:tax][:name]).to eq(update_params[:name])
        expect(json[:tax][:rate]).to eq(update_params[:rate])
        expect(json[:tax][:applied_to_organization]).to eq(update_params[:applied_to_organization])
      end
    end

    context 'when tax does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/taxes/unknown', {tax: update_params})

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when tax code already exists in organization scope (validation error)' do
      let(:tax2) { create(:tax, organization:) }
      let(:code) { tax2.code }

      before { tax2 }

      it 'returns unprocessable_entity error' do
        put_with_token(organization, "/api/v1/taxes/#{tax.code}", {tax: update_params})
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /taxes/:code' do
    let(:tax) { create(:tax, organization:) }

    it 'returns a tax' do
      get_with_token(organization, "/api/v1/taxes/#{tax.code}")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax][:lago_id]).to eq(tax.id)
        expect(json[:tax][:code]).to eq(tax.code)
      end
    end

    context 'when tax does not exist' do
      it 'returns not found' do
        get_with_token(organization, '/api/v1/taxes/unknown')
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /taxes/:code' do
    let(:tax) { create(:tax, organization:) }

    before { tax }

    it 'deletes a tax' do
      expect { delete_with_token(organization, "/api/v1/taxes/#{tax.code}") }
        .to change(Tax, :count).by(-1)
    end

    it 'returns deleted tax' do
      delete_with_token(organization, "/api/v1/taxes/#{tax.code}")

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:tax][:lago_id]).to eq(tax.id)
        expect(json[:tax][:code]).to eq(tax.code)
      end
    end

    context 'when tax does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/taxes/unknown')
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /taxes' do
    let(:tax) { create(:tax, organization:) }

    before { tax }

    it 'returns taxes' do
      get_with_token(organization, '/api/v1/taxes')

      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(json[:taxes].count).to eq(1)
        expect(json[:taxes].first[:lago_id]).to eq(tax.id)
        expect(json[:taxes].first[:code]).to eq(tax.code)
      end
    end

    context 'with pagination' do
      let(:tax2) { create(:tax, organization:) }

      before { tax2 }

      it 'returns taxes with correct meta data' do
        get_with_token(organization, '/api/v1/taxes?page=1&per_page=1')

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:taxes].count).to eq(1)
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
