# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Invoices::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:currency) { 'EUR' }
  let(:customer) { create(:customer, organization:) }
  let(:add_on_first) { create(:add_on, organization:) }
  let(:add_on_second) { create(:add_on, amount_cents: 400, organization:) }
  let(:fees) do
    [
      {
        addOnId: add_on_first.id,
        unitAmountCents: 1200,
        units: 2,
        description: 'desc-123',
      },
      {
        addOnId: add_on_second.id,
      },
    ]
  end
  let(:mutation) do
    <<-GQL
      mutation($input: CreateInvoiceInput!) {
        createInvoice(input: $input) {
          id,
          feesAmountCents,
          vatAmountCents,
          totalAmountCents,
          currency,
          vatRate,
          invoiceType,
          issuingDate
        }
      }
    GQL
  end

  it 'creates one-off invoice' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          currency:,
          fees:,
        },
      },
    )

    result_data = result['data']['createInvoice']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['issuingDate']).to eq(Time.current.to_date.to_s)
      expect(result_data['invoiceType']).to eq('one_off')
      expect(result_data['feesAmountCents']).to eq('2800')
      expect(result_data['vatAmountCents']).to eq('560')
      expect(result_data['totalAmountCents']).to eq('3360')
      expect(result_data['vatRate']).to eq(20)
      expect(result_data['currency']).to eq('EUR')
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            currency:,
            fees:,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            currency:,
            fees:,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
