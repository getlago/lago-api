# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::PlansResolver, type: :graphql do
  let(:required_permission) { 'plans:view' }
  let(:query) do
    <<~GQL
      query {
        plans(limit: 5) {
          collection { id chargesCount customersCount }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:plan) { create(:plan, organization:) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  before do
    plan
    customer

    2.times do
      create(:subscription, customer:, plan:)
    end
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'plans:view'

  it 'returns a list of plans' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
    )

    plans_response = result['data']['plans']

    aggregate_failures do
      expect(plans_response['collection'].count).to eq(organization.plans.count)
      expect(plans_response['collection'].first['id']).to eq(plan.id)
      expect(plans_response['collection'].first['customersCount']).to eq(1)

      expect(plans_response['metadata']['currentPage']).to eq(1)
      expect(plans_response['metadata']['totalCount']).to eq(1)
    end
  end
end
