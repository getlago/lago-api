# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::CreateFromTermination, type: :service do
  subject(:create_service) { described_class.new(subscription:) }

  let(:started_at) { Time.zone.parse('2022-09-01 10:00') }
  let(:subscription_at) { Time.zone.parse('2022-09-01 10:00') }
  let(:terminated_at) { Time.zone.parse('2022-10-15 10:00') }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:subscription) do
    create(
      :subscription,
      customer:,
      plan:,
      status: :terminated,
      subscription_at:,
      started_at:,
      terminated_at:,
      billing_time: :calendar
    )
  end

  let(:plan) do
    create(
      :plan,
      organization:,
      pay_in_advance: true,
      amount_cents: 31
    )
  end

  let(:subscription_fee) do
    create(
      :fee,
      subscription:,
      invoice:,
      amount_cents: 100,
      taxes_amount_cents: 20,
      invoiceable_type: 'Subscription',
      invoiceable_id: subscription.id,
      taxes_rate: 20
    )
  end

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      currency: 'EUR',
      fees_amount_cents: 100,
      total_amount_cents: 120
    )
  end

  let(:tax) { create(:tax, organization:, rate: 20) }

  describe '#call' do
    before { create(:fee_applied_tax, tax:, fee: subscription_fee) }

    it 'creates a credit note' do
      result = create_service.call

      aggregate_failures do
        expect(result).to be_success

        credit_note = result.credit_note
        expect(credit_note).to be_available
        expect(credit_note).to be_order_change
        expect(credit_note.total_amount_cents).to eq(19)
        expect(credit_note.total_amount_currency).to eq('EUR')
        expect(credit_note.credit_amount_cents).to eq(19)
        expect(credit_note.credit_amount_currency).to eq('EUR')
        expect(credit_note.balance_amount_cents).to eq(19)
        expect(credit_note.balance_amount_currency).to eq('EUR')
        expect(credit_note.reason).to eq('order_change')

        expect(credit_note.items.count).to eq(1)
      end
    end

    context 'when invoice is voided' do
      before { invoice.void! }

      it 'does not create a credit note' do
        expect { create_service.call }.not_to change(CreditNote, :count)
      end
    end

    context 'when fee amount is zero' do
      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 0,
          taxes_amount_cents: 0,
          invoiceable_type: 'Subscription',
          invoiceable_id: subscription.id,
          taxes_rate: 20
        )
      end

      it 'does not create a credit note' do
        expect { create_service.call }.not_to change(CreditNote, :count)
      end
    end

    context 'when multiple fees' do
      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 20,
          taxes_amount_cents: 4,
          invoiceable_type: 'Subscription',
          invoiceable_id: subscription.id,
          taxes_rate: 20,
          created_at: Time.current - 2.months
        )
      end

      let(:fee2) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 20,
          taxes_amount_cents: 4,
          invoiceable_type: 'Subscription',
          invoiceable_id: subscription.id,
          taxes_rate: 20,
          created_at: Time.current - 1.month
        )
      end

      before { fee2 }

      it 'takes the last fee as reference' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          credit_note = result.credit_note
          expect(credit_note.items.count).to eq(1)
          expect(credit_note.items.first.fee).to eq(fee2)
        end
      end
    end

    context 'when existing credit notes on the fee' do
      let(:credit_note) do
        create(
          :credit_note,
          customer: subscription.customer,
          invoice: subscription_fee.invoice,
          credit_amount_cents: 10
        )
      end

      let(:credit_note_item) do
        create(
          :credit_note_item,
          credit_note:,
          fee: subscription_fee,
          amount_cents: 10
        )
      end

      before { credit_note_item }

      it 'takes the remaining creditable amount' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          credit_note = result.credit_note
          expect(credit_note).to be_available
          expect(credit_note).to be_order_change
          expect(credit_note.total_amount_cents).to eq(7)
          expect(credit_note.total_amount_currency).to eq('EUR')
          expect(credit_note.credit_amount_cents).to eq(7)
          expect(credit_note.credit_amount_currency).to eq('EUR')
          expect(credit_note.balance_amount_cents).to eq(7)
          expect(credit_note.balance_amount_currency).to eq('EUR')
          expect(credit_note.reason).to eq('order_change')

          expect(credit_note.items.count).to eq(1)
        end
      end
    end

    context 'when plan has trial period ending after terminated_at' do
      let(:plan) do
        create(
          :plan,
          pay_in_advance: true,
          amount_cents: 31,
          trial_period: 46
        )
      end

      it 'excludes the trial from the credit amount' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          credit_note = result.credit_note
          expect(credit_note).to be_available
          expect(credit_note).to be_order_change
          expect(credit_note.total_amount_cents).to eq(18) # 15 * 1.2
          expect(credit_note.total_amount_currency).to eq('EUR')
          expect(credit_note.credit_amount_cents).to eq(18)
          expect(credit_note.credit_amount_currency).to eq('EUR')
          expect(credit_note.balance_amount_cents).to eq(18)
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
            trial_period: 120
          )
        end

        it 'does not creates a credit note' do
          expect { create_service.call }.not_to change(CreditNote, :count)
        end
      end
    end

    context 'when plan has been upgraded' do
      it 'calculates credit note correctly' do
        result = described_class.new(subscription:, upgrade: true).call

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
          expect(credit_note.reason).to eq('order_change')

          expect(credit_note.items.count).to eq(1)
        end
      end
    end

    context 'with a different timezone' do
      let(:started_at) { Time.zone.parse('2022-09-01 12:00') }
      let(:terminated_at) { Time.zone.parse('2022-10-15 01:00') }

      context 'when timezone shift is UTC -' do
        before { subscription.customer.update!(timezone: 'America/Los_Angeles') }

        it 'takes the timezone into account' do
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
            expect(credit_note.reason).to eq('order_change')

            expect(credit_note.items.count).to eq(1)
          end
        end
      end

      context 'when timezone shift is UTC +' do
        before { subscription.customer.update!(timezone: 'Europe/Paris') }

        it 'takes the timezone into account' do
          result = create_service.call

          aggregate_failures do
            expect(result).to be_success

            credit_note = result.credit_note
            expect(credit_note).to be_available
            expect(credit_note).to be_order_change
            expect(credit_note.total_amount_cents).to eq(19)
            expect(credit_note.total_amount_currency).to eq('EUR')
            expect(credit_note.credit_amount_cents).to eq(19)
            expect(credit_note.credit_amount_currency).to eq('EUR')
            expect(credit_note.balance_amount_cents).to eq(19)
            expect(credit_note.balance_amount_currency).to eq('EUR')
            expect(credit_note.reason).to eq('order_change')

            expect(credit_note.items.count).to eq(1)
          end
        end
      end
    end

    context 'with rounding at max precision' do
      let(:started_at) { Time.zone.parse('2023-01-30 10:00') }
      let(:subscription_at) { Time.zone.parse('2023-01-30 10:00') }
      let(:terminated_at) { Time.zone.parse('2023-03-14 10:00') }

      let(:subscription) do
        create(
          :subscription,
          plan:,
          customer:,
          status: :terminated,
          subscription_at:,
          started_at:,
          terminated_at:,
          billing_time: :anniversary
        )
      end

      let(:plan) do
        create(
          :plan,
          organization:,
          pay_in_advance: true,
          amount_cents: 999
        )
      end

      let(:invoice) do
        create(
          :invoice,
          customer:,
          currency: 'EUR',
          fees_amount_cents: 999,
          total_amount_cents: 0
        )
      end

      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 999,
          taxes_amount_cents: 0,
          invoiceable_type: 'Subscription',
          invoiceable_id: subscription.id,
          taxes_rate: 0,
          created_at: Time.zone.parse('2023-02-28 10:00'),
          amount_details: {'plan_amount_cents' => 999}
        )
      end

      it 'creates a credit note' do
        travel_to(terminated_at) do
          result = create_service.call

          aggregate_failures do
            expect(result).to be_success

            credit_note = result.credit_note
            expect(credit_note).to be_available
            expect(credit_note).to be_order_change
            expect(credit_note.total_amount_cents).to eq(499)
            expect(credit_note.total_amount_currency).to eq('EUR')
            expect(credit_note.credit_amount_cents).to eq(499)
            expect(credit_note.credit_amount_currency).to eq('EUR')
            expect(credit_note.balance_amount_cents).to eq(499)
            expect(credit_note.balance_amount_currency).to eq('EUR')
            expect(credit_note.reason).to eq('order_change')

            expect(credit_note.items.count).to eq(1)
          end
        end
      end
    end

    context 'with a coupon applied to the invoice' do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: 'EUR',
          fees_amount_cents: 100,
          total_amount_cents: 108,
          coupons_amount_cents: 10,
          taxes_amount_cents: 18,
          taxes_rate: 20
        )
      end

      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 100,
          taxes_amount_cents: 20,
          invoiceable_type: 'Subscription',
          invoiceable_id: subscription.id,
          taxes_rate: 20,
          precise_coupons_amount_cents: 10,
          amount_details: {'plan_amount_cents' => plan.amount_cents}
        )
      end

      it 'takes the coupon into account' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          credit_note = result.credit_note
          expect(credit_note).to have_attributes(
            total_amount_cents: 17,
            credit_amount_cents: 17,
            balance_amount_cents: 17
          )
        end
      end
    end

    context 'with no amount details attached to the fee' do
      let(:subscription_fee) do
        create(
          :fee,
          subscription:,
          invoice:,
          amount_cents: 999,
          taxes_amount_cents: 0,
          invoiceable_type: 'Subscription',
          invoiceable_id: subscription.id,
          taxes_rate: 0,
          created_at: Time.zone.parse('2023-02-28 10:00')
        )
      end

      it 'creates a credit note using the plan amount cents' do
        travel_to(terminated_at) do
          result = create_service.call

          aggregate_failures do
            expect(result).to be_success

            credit_note = result.credit_note
            expect(credit_note).to be_available
            expect(credit_note).to be_order_change
            expect(credit_note.total_amount_cents).to eq(19)
            expect(credit_note.total_amount_currency).to eq('EUR')
            expect(credit_note.credit_amount_cents).to eq(19)
            expect(credit_note.credit_amount_currency).to eq('EUR')
            expect(credit_note.balance_amount_cents).to eq(19)
            expect(credit_note.balance_amount_currency).to eq('EUR')
            expect(credit_note.reason).to eq('order_change')

            expect(credit_note.items.count).to eq(1)
          end
        end
      end
    end
  end
end
