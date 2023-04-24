# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AppliedAddOnsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:add_on) { create(:add_on, organization:) }

  describe 'create' do
    before do
      create(:active_subscription, customer:)
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

      aggregate_failures do
        expect(json[:applied_add_on][:lago_id]).to be_present
        expect(json[:applied_add_on][:lago_add_on_id]).to eq(add_on.id)
        expect(json[:applied_add_on][:lago_customer_id]).to eq(customer.id)
        expect(json[:applied_add_on][:external_customer_id]).to eq(customer.external_id)
        expect(json[:applied_add_on][:amount_cents]).to eq(add_on.amount_cents)
        expect(json[:applied_add_on][:amount_currency]).to eq(add_on.amount_currency)
        expect(json[:applied_add_on][:created_at]).to be_present
      end
    end

    context 'with invalid name' do
      let(:params) do
        { name: 'Foo Bar' }
      end

      it 'returns an not_found error' do
        post_with_token(organization, '/api/v1/applied_add_ons', { applied_add_on: params })

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
