# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Plans::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization: membership.organization) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyPlanInput!) {
        destroyPlan(input: $input) {
          id
        }
      }
    GQL
  end

  it 'deletes a plan' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: { id: plan.id }
      }
    )

    data = result['data']['destroyPlan']
    expect(data['id']).to eq(plan.id)
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: { id: plan.id }
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
