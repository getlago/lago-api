# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::OrganizationsController, type: :request do
  let(:organization) { create(:organization) }

  describe 'update' do
    let(:update_params) do
      {
        webhook_url: 'http://test.example',
        vat_rate: 20,
        country: 'pl',
        address_line1: 'address1',
        address_line2: 'address2',
        state: 'state',
        zipcode: '10000',
        email: 'mail@example.com',
        city: 'test_city',
        legal_name: 'test1',
        legal_number: '123',
        invoice_footer: 'footer',
        invoice_grace_period: 3,
      }
    end

    it 'updates an organization' do
      put_with_token(
        organization,
        '/api/v1/organizations',
        { organization: update_params },
      )

      expect(response).to have_http_status(:success)

      aggregate_failures do
        expect(json[:organization][:name]).to eq(organization.name)
        expect(json[:organization][:webhook_url]).to eq(update_params[:webhook_url])
        expect(json[:organization][:vat_rate]).to eq(update_params[:vat_rate])
        expect(json[:organization][:invoice_footer]).to eq(update_params[:invoice_footer])
        expect(json[:organization][:invoice_grace_period]).to eq(update_params[:invoice_grace_period])
      end
    end
  end
end
