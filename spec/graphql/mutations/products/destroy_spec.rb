# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Products::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product) { create(:product, organization: membership.organization) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyProductInput!) {
        destroyProduct(input: $input) {
          id
        }
      }
    GQL
  end

  it 'deletes a product' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: { id: product.id }
      }
    )

    data = result['data']['destroyProduct']
    expect(data['id']).to eq(product.id)
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: { id: product.id }
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
