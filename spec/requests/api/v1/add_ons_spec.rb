# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AddOnsController, type: :request do
  let(:organization) { create(:organization) }

  describe 'create' do
    let(:create_params) do
      {
        name: 'add_on1',
        code: 'add_on1_code',
        amount_cents: 123,
        amount_currency: 'EUR',
        description: 'description'
      }
    end

    it 'creates a add-on' do
      post_with_token(organization, '/api/v1/add_ons', { add_on: create_params })

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:add_on]
      expect(result[:lago_id]).to be_present
      expect(result[:code]).to eq(create_params[:code])
      expect(result[:name]).to eq(create_params[:name])
      expect(result[:created_at]).to be_present
    end
  end

  describe 'update' do
    let(:add_on) { create(:add_on, organization: organization) }
    let(:code) { 'add_on_code' }
    let(:update_params) do
      {
        name: 'add_on1',
        code: code,
        amount_cents: 123,
        amount_currency: 'EUR',
        description: 'description'
      }
    end

    it 'updates a add-on' do
      put_with_token(organization,
                     "/api/v1/add_ons/#{add_on.code}",
                     { add_on: update_params }
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:add_on]

      expect(result[:lago_id]).to eq(add_on.id)
      expect(result[:code]).to eq(update_params[:code])
    end

    context 'when add-on does not exist' do
      it 'returns not_found error' do
        put_with_token(organization, '/api/v1/add_ons/invalid', { add_on: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when add-on code already exists in organization scope (validation error)' do
      let(:add_on2) { create(:add_on, organization: organization) }
      let(:code) { add_on2.code }

      before { add_on2 }

      it 'returns unprocessable_entity error' do
        put_with_token(organization,
                       "/api/v1/add_ons/#{add_on.code}",
                       { add_on: update_params }
        )

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'show' do
    let(:add_on) { create(:add_on, organization: organization) }

    it 'returns a add-on' do
      get_with_token(
        organization,
        "/api/v1/add_ons/#{add_on.code}"
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:add_on]

      expect(result[:lago_id]).to eq(add_on.id)
      expect(result[:code]).to eq(add_on.code)
    end

    context 'when add-on does not exist' do
      it 'returns not found' do
        get_with_token(
          organization,
          "/api/v1/add_ons/555"
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'destroy' do
    let(:add_on) { create(:add_on, organization: organization) }

    before { add_on }

    it 'deletes a add-on' do
      expect { delete_with_token(organization, "/api/v1/add_ons/#{add_on.code}") }
        .to change(AddOn, :count).by(-1)
    end

    it 'returns deleted add-on' do
      delete_with_token(organization, "/api/v1/add_ons/#{add_on.code}")

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:add_on]

      expect(result[:lago_id]).to eq(add_on.id)
      expect(result[:code]).to eq(add_on.code)
    end

    context 'when add-on does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/add_ons/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'index' do
    let(:add_on) { create(:add_on, organization: organization) }

    before { add_on }

    it 'returns add-ons' do
      get_with_token(organization, '/api/v1/add_ons')

      expect(response).to have_http_status(:success)

      records = JSON.parse(response.body, symbolize_names: true)[:add_ons]

      expect(records.count).to eq(1)
      expect(records.first[:lago_id]).to eq(add_on.id)
      expect(records.first[:code]).to eq(add_on.code)
    end

    context 'with pagination' do
      let(:add_on2) { create(:add_on, organization: organization) }

      before { add_on2 }

      it 'returns add-ons with correct meta data' do
        get_with_token(organization, '/api/v1/add_ons?page=1&per_page=1')

        expect(response).to have_http_status(:success)

        response_body = JSON.parse(response.body, symbolize_names: true)

        expect(response_body[:add_ons].count).to eq(1)
        expect(response_body[:meta][:current_page]).to eq(1)
        expect(response_body[:meta][:next_page]).to eq(2)
        expect(response_body[:meta][:prev_page]).to eq(nil)
        expect(response_body[:meta][:total_pages]).to eq(2)
        expect(response_body[:meta][:total_count]).to eq(2)
      end
    end
  end
end
