# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CustomerPortal::OrganizationResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        customerPortalOrganization {
          id
          name
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  it_behaves_like 'requires a customer portal user'

  it 'returns the customer portal organization' do
    result = execute_graphql(
      customer_portal_user: customer,
      query:,
    )

    data = result['data']['customerPortalOrganization']

    aggregate_failures do
      expect(data['id']).to eq(organization.id)
      expect(data['name']).to eq(organization.name)
    end
  end
end
