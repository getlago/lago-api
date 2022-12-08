# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::CreateFromUpgrade, type: :service do
  subject(:create_service) { described_class.new(subscription: subscription) }

  let(:started_at) { Time.zone.parse('2022-09-01 10:00') }
  let(:subscription_date) { Time.zone.parse('2022-09-01 10:00') }
  let(:terminated_at) { Time.zone.parse('2022-10-15 10:00') }

  let(:subscription) do
    create(
      :subscription,
      plan: plan,
      status: :terminated,
      subscription_date: subscription_date,
      started_at: started_at,
      terminated_at: terminated_at,
      billing_time: :calendar,
    )
  end

  let(:plan) do
    create(
      :plan,
      pay_in_advance: true,
      amount_cents: 31,
    )
  end

  let(:subscription_fee) do
    create(
      :fee,
      subscription: subscription,
      invoice: invoice,
      amount_cents: 100,
      vat_amount_cents: 20,
      invoiceable_type: 'Subscription',
      invoiceable_id: subscription.id,
      vat_rate: 20,
    )
  end

  let(:invoice) do
    create(
      :invoice,
      customer: subscription.customer,
      amount_currency: 'EUR',
      amount_cents: 100,
      total_amount_currency: 'EUR',
      total_amount_cents: 120,
    )
  end

  describe '.call' do
    before { subscription_fee }

    it 'creates a credit note' do
      result = create_service.call

      aggregate_failures do
        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note).to be_available
        expect(credit_note).to be_order_change
        expect(credit_note.total_amount_cents).to eq(20)
        expect(credit_note.total_amount_currency).to eq('EUR')
        expect(credit_note.credit_amount_cents).to eq(20)
        expect(credit_note.credit_amount_currency).to eq('EUR')
        expect(credit_note.balance_amount_cents).to eq(20)
        expect(credit_note.balance_amount_currency).to eq('EUR')

        expect(credit_note.items.count).to eq(1)
      end
    end

    context 'when fee amount is zero' do
      let(:subscription_fee) do
        create(
          :fee,
          subscription: subscription,
          invoice: invoice,
          amount_cents: 0,
          vat_amount_cents: 0,
          invoiceable_type: 'Subscription',
          invoiceable_id: subscription.id,
          vat_rate: 20,
        )
      end

      it 'does not create a credit note' do
        expect { create_service.call }.not_to change(CreditNote, :count)
      end
    end

    context 'when plan has trial period ending after terminated_at' do
      let(:plan) do
        create(
          :plan,
          pay_in_advance: true,
          amount_cents: 31,
          trial_period: 46,
        )
      end

      it 'excludes the trial from the credit amount' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          credit_note = result.credit_note
          expect(credit_note).to be_available
          expect(credit_note).to be_order_change
          expect(credit_note.total_amount_cents).to eq(17)
          expect(credit_note.total_amount_currency).to eq('EUR')
          expect(credit_note.credit_amount_cents).to eq(17)
          expect(credit_note.credit_amount_currency).to eq('EUR')
          expect(credit_note.balance_amount_cents).to eq(17)
          expect(credit_note.balance_amount_currency).to eq('EUR')

          expect(credit_note.items.count).to eq(1)
        end
      end

      context 'when trial ends after the end of the billing period' do
        let(:plan) do
          create(
            :plan,
            pay_in_advance: true,
            amount_cents: 31,
            trial_period: 120,
          )
        end

        it 'does not creates a credit note' do
          expect { create_service.call }.not_to change(CreditNote, :count)
        end
      end
    end
  end
end
