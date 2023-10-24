# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CreditNotes::EstimateResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($invoiceId: ID!, $items: [CreditNoteItemInput!]!) {
        creditNoteEstimate(invoiceId: $invoiceId, items: $items) {
          currency
          taxesAmountCents
          subTotalExcludingTaxesAmountCents
          maxCreditableAmountCents
          couponsAdjustmentAmountCents
          taxesRate
          items { amountCents fee { id } }
          appliedTaxes { id amountCents }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:fees) { create_list(:fee, 2, invoice:, amount_cents: 100) }

  around { |test| lago_premium!(&test) }

  it 'returns the estimate for the credit note creation' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {
        invoiceId: invoice.id,
        items: fees.map { |f| { feeId: f.id, amountCents: 50 } },
      },
    )

    estimate_response = result['data']['creditNoteEstimate']

    aggregate_failures do
      expect(estimate_response['currency']).to eq('EUR')
      expect(estimate_response['taxesAmountCents']).to eq('0')
      expect(estimate_response['subTotalExcludingTaxesAmountCents']).to eq('0')
      expect(estimate_response['maxCreditableAmountCents']).to eq('100')
      expect(estimate_response['couponsAdjustmentAmountCents']).to eq('0')
      expect(estimate_response['items'].first['amountCents']).to eq('50')
      expect(estimate_response['appliedTaxes']).to be_blank
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query:,
        variables: {
          invoiceId: invoice.id,
          items: fees.map { |f| { feeId: f.id, amountCents: 50 } },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {
          invoiceId: invoice.id,
          items: fees.map { |f| { feeId: f.id, amountCents: 50 } },
        },
      )

      expect_forbidden_error(result)
    end
  end

  context 'with invalid invoice' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {
          invoiceId: create(:invoice).id,
          items: fees.map { |f| { feeId: f.id, amountCents: 50 } },
        },
      )

      expect_not_found(result)
    end
  end
end
