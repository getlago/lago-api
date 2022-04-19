# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::SubscriptionService do
  subject(:fees_subscription_service) { described_class.new(invoice) }

  let(:plan) do
    create(
      :plan,
      amount_cents: 100,
      amount_currency: 'EUR',
      vat_rate: 20,
    )
  end

  context 'when invoice is on a full period' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: Time.zone.now - 3.months,
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: (Time.zone.now - 1.month).beginning_of_month,
        to_date: (Time.zone.now - 1.month).end_of_month,
      )
    end

    it 'creates a fee' do
      result = fees_subscription_service.create
      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.id).not_to be_nil
        expect(created_fee.invoice_id).to eq(invoice.id)
        expect(created_fee.amount_cents).to eq(plan.amount_cents)
        expect(created_fee.amount_currency).to eq(plan.amount_currency)
        expect(created_fee.vat_amount_cents).to eq(20)
        expect(created_fee.vat_rate).to eq(20.0)
      end
    end
  end

  context 'when subscription has never been billed' do
    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.end_of_month.to_date,
      )
    end

    context 'when plan is monthly' do
      before { plan.monthly! }

      context 'when subscription start is on the 1st of the month' do
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: (Time.zone.now - 3.months).beginning_of_month,
          )
        end

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(plan.amount_cents)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(20)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(100)
            end
          end
        end
      end

      context 'when subscription start is on any other day' do
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: Time.zone.parse('2022-03-15 00:00:00'),
          )
        end

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(54)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(10)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(54)
            end
          end
        end
      end
    end

    context 'when plan is yearly' do
      before { plan.yearly! }

      context 'when subscription start is on the 1st day of the year' do
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: Time.zone.now.beginning_of_year,
          )
        end

        before do
          invoice.update!(
            from_date: subscription.started_at.beginning_of_year,
            to_date: subscription.started_at.end_of_year,
          )
        end

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(plan.amount_cents)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(20)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(plan.amount_cents)
            end
          end
        end
      end

      context 'when subscription start is on any other day' do
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: Time.zone.parse('2022-03-15 00:00:00'),
          )
        end

        before { invoice.update!(to_date: subscription.started_at.end_of_year) }

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(80)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(16)
            expect(created_fee.vat_rate).to eq(20.0)
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(80)
            end
          end
        end
      end
    end
  end

  context 'when subscription has already been billed once on an other period' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: Time.zone.now - 3.month,
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.end_of_month.to_date,
      )
    end

    before do
      other_invoice = create(:invoice, subscription: subscription)
      create(:fee, subscription: subscription, invoice: other_invoice)
    end

    it 'creates a fee with full period amount' do
      result = fees_subscription_service.create
      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.amount_cents).to eq(100)
      end
    end
  end

  context 'when plan interval is not implemented' do
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: (Time.zone.now - 2.week).beginning_of_week,
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.end_of_month.to_date,
      )
    end

    before do
      plan.weekly!
    end

    it 'throws an NotImpementedError' do
      expect { fees_subscription_service.create }.to raise_error(NotImplementedError)
    end
  end

  context 'when already billed fee' do
    let(:plan) do
      create(
        :plan,
        amount_cents: 100,
        amount_currency: 'EUR',
        vat_rate: 20,
      )
    end

    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: Time.zone.now - 3.month,
      )
    end

    let(:invoice) do
      create(
        :invoice,
        subscription: subscription,
        from_date: subscription.started_at + 1.month,
        to_date: subscription.started_at + 2.month,
      )
    end

    before do
      create(:fee, subscription: subscription, invoice: invoice)
    end

    it 'creates a fee' do
      expect { fees_subscription_service.create }.to_not change { Fee.count }
    end
  end

  context 'when billing a just terminated subscription' do

  end

  context 'when billing an new upgraded subscription' do

  end
end
