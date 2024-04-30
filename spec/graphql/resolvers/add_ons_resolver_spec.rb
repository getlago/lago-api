# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::AddOnsResolver, type: :graphql do
  let(:required_permission) { 'addons:view' }
  let(:query) do
    <<~GQL
      query {
        addOns(limit: 5) {
          collection { id name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:add_on) { create(:add_on, organization:) }

  before { add_on }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'addons:view'

  it 'returns a list of add-ons' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
    )

    add_ons_response = result['data']['addOns']

    aggregate_failures do
      expect(add_ons_response['collection'].first['id']).to eq(add_on.id)
      expect(add_ons_response['collection'].first['name']).to eq(add_on.name)

      expect(add_ons_response['metadata']['currentPage']).to eq(1)
      expect(add_ons_response['metadata']['totalCount']).to eq(1)
    end
  end
end
