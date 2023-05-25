# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::CreditNotes::Create, type: :graphql do
  let(:organization) { create(:organization) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }

  let(:fee1) { create(:fee, invoice:) }
  let(:fee2) { create(:charge_fee, invoice:) }

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      payment_status: 'succeeded',
      currency: 'EUR',
      fees_amount_cents: 100,
      taxes_amount_cents: 120,
      total_amount_cents: 120,
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
          description
          currency
          totalAmountCents
          creditAmountCents
          balanceAmountCents
          refundAmountCents
          items {
            id
            amountCents
            amountCurrency
            fee { id }
          }
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  it 'creates a credit note' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          reason: 'duplicated_charge',
          invoiceId: invoice.id,
          description: 'Duplicated charge',
          creditAmountCents: 10,
          refundAmountCents: 5,
          items: [
            {
              feeId: fee1.id,
              amountCents: 10,
            },
            {
              feeId: fee2.id,
              amountCents: 5,
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
      expect(result_data['description']).to eq('Duplicated charge')
      expect(result_data['currency']).to eq('EUR')
      expect(result_data['totalAmountCents']).to eq('15')
      expect(result_data['creditAmountCents']).to eq('10')
      expect(result_data['balanceAmountCents']).to eq('10')
      expect(result_data['refundAmountCents']).to eq('5')

      expect(result_data['items'][0]['id']).to be_present
      expect(result_data['items'][0]['amountCents']).to eq('10')
      expect(result_data['items'][0]['amountCurrency']).to eq('EUR')
      expect(result_data['items'][0]['fee']['id']).to eq(fee1.id)

      expect(result_data['items'][1]['id']).to be_present
      expect(result_data['items'][1]['amountCents']).to eq('5')
      expect(result_data['items'][1]['amountCurrency']).to eq('EUR')
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
            creditAmountCents: 10,
            refundAmountCents: 5,
            items: [
              {
                feeId: fee1.id,
                amountCents: 15,
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
            creditAmountCents: 10,
            refundAmountCents: 5,
            items: [
              {
                feeId: fee1.id,
                amountCents: 15,
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
            creditAmountCents: 10,
            refundAmountCents: 5,
            items: [
              {
                feeId: fee1.id,
                amountCents: 15,
              },
            ],
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
