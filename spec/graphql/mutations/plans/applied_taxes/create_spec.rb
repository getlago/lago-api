# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Plans::AppliedTaxes::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:mutation) do
    <<-GQL
      mutation($input: CreatePlanAppliedTaxInput!) {
        createPlanAppliedTax(input: $input) {
          id
          tax { id }
          plan { id }
          createdAt
        }
      }
    GQL
  end

  let(:tax) { create(:tax, organization:) }
  let(:plan) { create(:plan, organization:) }

  it 'assigns a tax to the plan' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: { taxId: tax.id, planId: plan.id },
      },
    )

    result_data = result['data']['createPlanAppliedTax']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['tax']['id']).to eq(tax.id)
      expect(result_data['plan']['id']).to eq(plan.id)
      expect(result_data['createdAt']).to be_present
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: { taxId: tax.id, planId: plan.id },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.id,
        query: mutation,
        variables: {
          input: { taxId: tax.id, planId: plan.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
