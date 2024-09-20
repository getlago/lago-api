# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CustomerPortal::OrganizationResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        customerPortalOrganization {
          id
          name
          billingConfiguration {
            id
            documentLocale
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  it_behaves_like 'requires a customer portal user'

  it 'returns the customer portal organization' do
    result = execute_customer_portal_graphql(
      customer_portal_user: customer,
      query:
    )

    data = result['data']['customerPortalOrganization']

    aggregate_failures do
      expect(data['id']).to eq(organization.id)
      expect(data['name']).to eq(organization.name)
      expect(data['billingConfiguration']['id']).to eq("#{organization.id}-c0nf")
      expect(data['billingConfiguration']['documentLocale']).to eq('en')
    end
  end
end
