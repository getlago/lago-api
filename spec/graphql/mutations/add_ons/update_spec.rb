# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::AddOns::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:) }
  let(:tax2) { create(:tax, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateAddOnInput!) {
        updateAddOn(input: $input) {
          id,
          name,
          invoiceDisplayName,
          code,
          description,
          amountCents,
          amountCurrency,
          taxes { id code rate }
        }
      }
    GQL
  end

  before { create(:add_on_applied_tax, add_on:, tax:) }

  it 'updates an add-on' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: add_on.id,
          name: 'New name',
          invoiceDisplayName: 'New invoice name',
          code: 'new_code',
          description: 'desc',
          amountCents: 123,
          amountCurrency: 'USD',
          taxCodes: [tax2.code],
        },
      },
    )

    result_data = result['data']['updateAddOn']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
      expect(result_data['invoiceDisplayName']).to eq('New invoice name')
      expect(result_data['code']).to eq('new_code')
      expect(result_data['description']).to eq('desc')
      expect(result_data['amountCents']).to eq('123')
      expect(result_data['amountCurrency']).to eq('USD')
      expect(result_data['taxes'].map { |t| t['code'] }).to contain_exactly(tax2.code)
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: add_on.id,
            name: 'New name',
            code: 'new_code',
            amountCents: 123,
            amountCurrency: 'USD',
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
