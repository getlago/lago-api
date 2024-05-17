# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::OrganizationsController, type: [:request, :admin] do
  let(:organization) { create(:organization) }

  describe 'PUT /admin/organizations/:id' do
    let(:update_params) do
      {
        name: 'FooBar'
      }
    end

    it 'updates an organization' do
      admin_put(
        "/admin/organizations/#{organization.id}",
        update_params,
      )

      expect(response).to have_http_status(:success)

      aggregate_failures do
        expect(json[:organization][:name]).to eq('FooBar')
        expect(organization.reload.name).to eq('FooBar')
      end
    end
  end
end
