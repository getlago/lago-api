# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::EstimateService, type: :service do
  subject(:estimate_service) { described_class.new(invoice:, items:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      currency: 'EUR',
      fees_amount_cents: 20,
      coupons_amount_cents: 10,
      taxes_amount_cents: 2,
      total_amount_cents: 12,
      payment_status: :succeeded,
      taxes_rate: 20,
      version_number: 3
    )
  end

  let(:fee1) do
    create(:fee, invoice:, amount_cents: 10, taxes_amount_cents: 1, taxes_rate: 20, precise_coupons_amount_cents: 5)
  end

  let(:fee2) do
    create(:fee, invoice:, amount_cents: 10, taxes_amount_cents: 1, taxes_rate: 20, precise_coupons_amount_cents: 5)
  end

  let(:tax) { create(:tax, organization:, rate: 20) }

  let(:items) do
    [
      {
        fee_id: fee1.id,
        amount_cents: 10
      },
      {
        fee_id: fee2.id,
        amount_cents: 5
      }
    ]
  end

  around { |test| lago_premium!(&test) }

  before do
    create(:fee_applied_tax, tax:, fee: fee1)
    create(:fee_applied_tax, tax:, fee: fee2)
    create(:invoice_applied_tax, tax:, invoice:) if invoice
  end

  it 'estimates the credit and refund amount' do
    result = estimate_service.call

    aggregate_failures do
      expect(result).to be_success

      credit_note = result.credit_note
      expect(credit_note).to have_attributes(
        invoice:,
        customer:,
        currency: invoice.currency,
        credit_amount_cents: 9,
        refund_amount_cents: 9,
        coupons_adjustment_amount_cents: 8,
        taxes_amount_cents: 2,
        taxes_rate: 20
      )

      expect(credit_note.applied_taxes.size).to eq(1)

      expect(credit_note.items.size).to eq(2)

      item1 = credit_note.items.first
      expect(item1).to have_attributes(
        fee: fee1,
        amount_cents: 10,
        amount_currency: invoice.currency
      )

      item2 = credit_note.items.last
      expect(item2).to have_attributes(
        fee: fee2,
        amount_cents: 5,
        amount_currency: invoice.currency
      )
    end
  end

  context 'with invalid items' do
    let(:items) do
      [
        {
          fee_id: fee1.id,
          amount_cents: 10
        },
        {
          fee_id: fee2.id,
          amount_cents: 15
        }
      ]
    end

    it 'returns a failed result' do
      result = estimate_service.call

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:amount_cents)
        expect(result.error.messages[:amount_cents]).to eq(
          %w[
            higher_than_remaining_fee_amount
          ]
        )
      end
    end
  end

  context 'with missing items' do
    let(:items) {}

    it 'returns a failed result' do
      result = estimate_service.call

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages.keys).to include(:items)
      expect(result.error.messages[:items]).to eq(
        %w[
          must_be_an_array
        ]
      )
    end
  end

  context 'when invoice is not found' do
    let(:invoice) { nil }
    let(:items) { [] }

    it 'returns a failure' do
      result = estimate_service.call

      aggregate_failures do
        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq('invoice_not_found')
      end
    end
  end

  context 'when invoice is legacy' do
    let(:invoice) do
      create(
        :invoice,
        currency: 'EUR',
        sub_total_excluding_taxes_amount_cents: 20,
        total_amount_cents: 24,
        payment_status: :succeeded,
        taxes_rate: 20,
        version_number: 1
      )
    end

    it 'returns a failure' do
      result = estimate_service.call

      aggregate_failures do
        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq('invalid_type_or_status')
      end
    end
  end

  context 'when invoice is a prepaid credit invoice' do
    let(:invoice) do
      create(
        :invoice,
        invoice_type: :credit,
        organization:,
        customer:,
        currency: 'EUR',
        fees_amount_cents: 20,
        total_amount_cents: 12,
        payment_status: :succeeded,
        version_number: 3
      )
    end
    let(:wallet) { create(:wallet, customer:, balance_cents: 10) }
    let(:wallet_transaction) { create(:wallet_transaction, wallet:) }
    let(:credit_fee) { create(:fee, fee_type: :credit, invoice:, invoiceable: wallet_transaction) }
    let(:items) do
      [
        {
          fee_id: credit_fee.id,
          amount_cents: 3
        }
      ]
    end

    before { credit_fee }

    context 'when wallet for the credits is active' do
      it 'estimates the credit and refund amount not higher than wallet.balance_cents' do
        result = estimate_service.call

        aggregate_failures do
          expect(result).to be_success

          credit_note = result.credit_note
          expect(credit_note).to have_attributes(
            currency: invoice.currency,
            credit_amount_cents: 0,
            refund_amount_cents: 3,
            coupons_adjustment_amount_cents: 0,
            taxes_amount_cents: 0,
            taxes_rate: 0
          )
        end
      end

      context 'when estimating with amount higher than in the active wallet' do
        let(:items) do
          [
            {
              fee_id: credit_fee.id,
              amount_cents: 50
            }
          ]
        end

        it 'returns a failure' do
          result = estimate_service.call

          aggregate_failures do
            expect(result).not_to be_success

            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:amount_cents)
            expect(result.error.messages[:amount_cents]).to eq(
              %w[
                higher_than_wallet_balance
              ]
            )
          end
        end
      end
    end

    context 'when wallet for the credits is not active' do
      let(:wallet) { create(:wallet, customer:, balance_cents: 10, status: :terminated) }

      it 'estimates the credit and refund amount hot higher than wallet.balance_amount_cents' do
        result = estimate_service.call

        aggregate_failures do
          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        end
      end
    end
  end
end
