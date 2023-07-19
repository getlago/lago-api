# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Plans::AppliedTaxes::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:applied_tax) { create(:plan_applied_tax, tax:, plan:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyPlanAppliedTaxInput!) {
        destroyPlanAppliedTax(input: $input) { id }
      }
    GQL
  end

  before { applied_tax }

  it 'destroys an applied tax' do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: mutation,
        variables: {
          input: { id: applied_tax.id },
        },
      )
    end.to change(Plan::AppliedTax, :count).by(-1)
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: { id: applied_tax.id },
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
          input: { id: applied_tax.id },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
