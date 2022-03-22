# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Products::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product) { create(:product, organization: organization) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateProductInput!) {
        updateProduct(input: $input) {
          id,
          name,
          billableMetrics { id, name }
        }
      }
    GQL
  end

  let(:billable_metrics) do
    create_list(:billable_metric, 4, organization: organization)
  end

  it 'updates a product' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: product.id,
          name: 'Updated product',
          billableMetricIds: billable_metrics.map(&:id)
        }
      }
    )

    result_data = result['data']['updateProduct']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('Updated product')
      expect(result_data['billableMetrics'].count).to eq(4)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: product.id,
            name: 'Updated product',
            billableMetricIds: billable_metrics.map(&:id)
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
