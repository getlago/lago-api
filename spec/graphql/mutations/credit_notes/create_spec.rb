# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::CreditNotes::Create, type: :graphql do
  let(:membership) { create(:membership, organization: organization) }
  let(:organization) { invoice.organization }

  let(:fee1) { create(:fee, invoice: invoice) }
  let(:fee2) { create(:charge_fee, invoice: invoice) }

  let(:invoice) do
    create(
      :invoice,
      status: 'succeeded',
      amount_cents: 100,
      amount_currency: 'EUR',
      vat_amount_cents: 120,
      vat_amount_currency: 'EUR',
      total_amount_cents: 120,
      total_amount_currency: 'EUR',
    )
  end

  let(:mutation) do
    <<~GQL
      mutation($input: CreateCreditNoteInput!) {
        createCreditNote(input: $input) {
          id
          creditStatus
          refundStatus
          reason
          totalAmountCents
          totalAmountCurrency
          creditAmountCents
          creditAmountCurrency
          balanceAmountCents
          balanceAmountCurrency
          refundAmountCents
          refundAmountCurrency
          items {
            id
            creditAmountCents
            creditAmountCurrency
            refundAmountCents
            refundAmountCurrency
            fee { id }
          }
        }
      }
    GQL
  end

  it 'creates a credit note' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          reason: 'duplicated_charge',
          invoiceId: invoice.id,
          items: [
            {
              feeId: fee1.id,
              creditAmountCents: 10,
              refundAmountCents: 5,
            },
            {
              feeId: fee2.id,
              creditAmountCents: 5,
              refundAmountCents: 10,
            },
          ],
        },
      },
    )

    result_data = result['data']['createCreditNote']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['creditStatus']).to eq('available')
      expect(result_data['refundStatus']).to eq('pending')
      expect(result_data['reason']).to eq('duplicated_charge')
      expect(result_data['totalAmountCents']).to eq('30')
      expect(result_data['totalAmountCurrency']).to eq('EUR')
      expect(result_data['creditAmountCents']).to eq('15')
      expect(result_data['creditAmountCurrency']).to eq('EUR')
      expect(result_data['balanceAmountCents']).to eq('15')
      expect(result_data['balanceAmountCurrency']).to eq('EUR')
      expect(result_data['refundAmountCents']).to eq('15')
      expect(result_data['refundAmountCurrency']).to eq('EUR')

      expect(result_data['items'][0]['id']).to be_present
      expect(result_data['items'][0]['creditAmountCents']).to eq('10')
      expect(result_data['items'][0]['creditAmountCurrency']).to eq('EUR')
      expect(result_data['items'][0]['refundAmountCents']).to eq('5')
      expect(result_data['items'][0]['refundAmountCurrency']).to eq('EUR')
      expect(result_data['items'][0]['fee']['id']).to eq(fee1.id)

      expect(result_data['items'][1]['id']).to be_present
      expect(result_data['items'][1]['creditAmountCents']).to eq('5')
      expect(result_data['items'][1]['creditAmountCurrency']).to eq('EUR')
      expect(result_data['items'][1]['refundAmountCents']).to eq('10')
      expect(result_data['items'][1]['refundAmountCurrency']).to eq('EUR')
      expect(result_data['items'][1]['fee']['id']).to eq(fee2.id)
    end
  end

  context 'when invoice is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: mutation,
        variables: {
          input: {
            reason: 'duplicated_charge',
            invoiceId: 'foo_id',
            items: [
              {
                feeId: fee1.id,
                creditAmountCents: 10,
                refundAmountCents: 5,
              },
            ],
          },
        },
      )

      expect_not_found(result)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: organization,
        query: mutation,
        variables: {
          input: {
            reason: 'duplicated_charge',
            invoiceId: invoice.id,
            items: [
              {
                feeId: fee1.id,
                creditAmountCents: 10,
                refundAmountCents: 5,
              },
            ],
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
            reason: 'duplicated_charge',
            invoiceId: invoice.id,
            items: [
              {
                feeId: fee1.id,
                creditAmountCents: 10,
                refundAmountCents: 5,
              },
            ],
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
