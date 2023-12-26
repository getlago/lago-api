# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::AdjustedFees::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:invoice) { create(:invoice, status: :draft, organization:) }
  let(:fee) { create(:charge_fee, invoice:) }
  let(:adjusted_fee) { create(:adjusted_fee, invoice:, fee:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyAdjustedFeeInput!) {
        destroyAdjustedFee(input: $input) { id }
      }
    GQL
  end

  before { adjusted_fee }

  it 'destroys an adjusted fee' do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: { input: { id: fee.id } },
      )
    end.to change(AdjustedFee, :count).by(-1)
  end

  context 'without current_organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: { input: { id: fee.id } },
      )

      expect_forbidden_error(result)
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: { input: { id: fee.id } },
      )

      expect_unauthorized_error(result)
    end
  end
end
