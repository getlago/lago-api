# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AppliedAddOnsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:add_on) { create(:add_on, organization: organization) }

  describe 'create' do
    before do
      create(:active_subscription, customer: customer)
    end

    let(:params) do
      {
        external_customer_id: customer.external_id,
        add_on_code: add_on.code,
      }
    end

    it 'returns a success' do
      post_with_token(
        organization,
        '/api/v1/applied_add_ons',
        { applied_add_on: params },
      )

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:applied_add_on]

      aggregate_failures do
        expect(result[:lago_id]).to be_present
        expect(result[:lago_add_on_id]).to eq(add_on.id)
        expect(result[:lago_customer_id]).to eq(customer.id)
        expect(result[:external_customer_id]).to eq(customer.external_id)
        expect(result[:amount_cents]).to eq(add_on.amount_cents)
        expect(result[:amount_currency]).to eq(add_on.amount_currency)
        expect(result[:created_at]).to be_present
      end
    end

    context 'with invalid params' do
      let(:params) do
        {
          name: 'Foo Bar',
        }
      end

      it 'returns an unprocessable_entity' do
        post_with_token(organization, '/api/v1/applied_add_ons', { applied_add_on: params })

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
