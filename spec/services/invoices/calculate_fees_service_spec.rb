# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CalculateFeesService, type: :service do
  subject(:invoice_service) do
    described_class.new(
      invoice: invoice,
      subscriptions: subscriptions,
      timestamp: timestamp.to_i,
      invoice_source: invoice_source,
    )
  end

  let(:invoice_source) { :initial }

  describe '#call' do
    let(:invoice) do
      create(
        :invoice,
        amount_currency: 'EUR',
        vat_amount_currency: 'EUR',
        total_amount_currency: 'EUR',
        issuing_date: Time.zone.at(timestamp).to_date,
        customer: subscription.customer,
      )
    end

    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        subscription_at: started_at.to_date,
        started_at: started_at,
        created_at: started_at,
      )
    end
    let(:subscriptions) { [subscription] }

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:timestamp) { Time.zone.now.beginning_of_month }
    let(:started_at) { Time.zone.now - 2.years }

    let(:plan) { create(:plan, interval: 'monthly', pay_in_advance: pay_in_advance) }
    let(:pay_in_advance) { false }

    before do
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::Payments::StripeCreateJob).to receive(:perform_later).and_call_original
      allow(Invoices::Payments::GocardlessCreateJob).to receive(:perform_later).and_call_original
    end

    context 'when billed monthly' do
      context 'when plan is pay in advance and subscription fees are created earlier today' do
        let(:pay_in_advance) { true }
        let(:timestamp) { Time.current.to_i }

        before { create(:fee, subscription: subscription) }

        it 'does not create any subscription fees' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.subscription_kind.count).to eq(0)

            expect(result.invoice.invoice_subscriptions.count).to eq(1)
            expect(result.invoice.invoice_subscriptions.first).to be_initial
          end
        end
      end

      context 'when plan is pay in advance and subscription started in the past' do
        let(:pay_in_advance) { true }
        let(:created_at) { timestamp }
        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_at: started_at.to_date,
            started_at: started_at,
            created_at: timestamp,
          )
        end

        it 'creates charge fees' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.charge_kind.count).to eq(1)
          end
        end
      end

      context 'when plan is pay in advance and subscription started on creation day' do
        let(:pay_in_advance) { true }

        it 'does not create any charge fees' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.charge_kind.count).to eq(0)
          end
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Mar 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2021').to_date }
        let(:subscription_at) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_at: subscription_at,
            started_at: started_at,
            billing_time: :anniversary,
            created_at: started_at,
          )
        end

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice.fees.first.properties['to_datetime']).to match_datetime('2022-03-05 23:59:59')
            expect(result.invoice.fees.first.properties['from_datetime']).to match_datetime('2022-02-06 00:00:00')
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.payment_status).to eq('pending')
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
            expect(result.invoice.fees.charge_kind.count).to eq(1)
            expect(result.invoice.amount_cents).to eq(100)
            expect(result.invoice.vat_amount_cents).to eq(20)
            expect(result.invoice.credit_amount_cents).to eq(0)
            expect(result.invoice.total_amount_cents).to eq(120)
          end
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'updates the invoice accordingly' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.invoice.fees.first.properties['to_datetime']).to match_datetime('2022-04-05 23:59:59')
              expect(result.invoice.fees.first.properties['from_datetime']).to match_datetime('2022-03-06 00:00:00')
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.payment_status).to eq('pending')
              expect(result.invoice.fees.subscription_kind.count).to eq(1)
              expect(result.invoice.fees.charge_kind.count).to eq(0)
              expect(result.invoice.amount_cents).to eq(100)
              expect(result.invoice.vat_amount_cents).to eq(20)
              expect(result.invoice.credit_amount_cents).to eq(0)
              expect(result.invoice.total_amount_cents).to eq(120)
            end
          end
        end
      end
    end

    context 'when billed monthly and two subscriptions are given' do
      let(:subscription2) do
        create(
          :subscription,
          plan: plan,
          customer: subscription.customer,
          subscription_at: (Time.zone.now - 2.years).to_date,
          started_at: Time.zone.now - 2.years,
        )
      end
      let(:subscriptions) { [subscription, subscription2] }

      it 'updates the invoice accordingly based on both subscription' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.fees.first.properties['to_datetime'])
            .to match_datetime((timestamp - 1.day).end_of_day)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime((timestamp - 1.month).beginning_of_day)
          expect(result.invoice.subscriptions).to eq(subscriptions)
          expect(result.invoice.payment_status).to eq('pending')
          expect(result.invoice.fees.subscription_kind.count).to eq(2)
          expect(result.invoice.fees.charge_kind.count).to eq(2)
          expect(result.invoice.amount_cents).to eq(200)
          expect(result.invoice.vat_amount_cents).to eq(40)
          expect(result.invoice.credit_amount_cents).to eq(0)
          expect(result.invoice.total_amount_cents).to eq(240)
        end
      end
    end

    context 'when billed monthly on first month' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { timestamp - 3.days }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_at: started_at.to_date,
          started_at: started_at,
          created_at: started_at,
        )
      end

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_datetime'])
            .to match_datetime((timestamp - 1.day).end_of_day)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime(subscription.subscription_at.beginning_of_day)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed weekly' do
      let(:timestamp) { Time.zone.now.beginning_of_week }

      let(:plan) do
        create(:plan, interval: 'weekly', pay_in_advance: pay_in_advance)
      end

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_datetime'])
            .to match_datetime((timestamp - 1.day).end_of_day)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime((timestamp - 1.week).beginning_of_day)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Mar 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2021').to_date }
        let(:subscription_at) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_at: subscription_at,
            started_at: started_at,
            billing_time: :anniversary,
            created_at: started_at,
          )
        end

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.fees.first.properties['to_datetime']).to match_datetime('2022-03-05 23:59:59')
            expect(result.invoice.fees.first.properties['from_datetime']).to match_datetime('2022-02-27 00:00:00')
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
            expect(result.invoice.fees.charge_kind.count).to eq(1)
          end
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'updates the invoice accordingly' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(result.invoice.fees.first.properties['to_datetime']).to match_datetime('2022-03-12 23:59:59')
              expect(result.invoice.fees.first.properties['from_datetime']).to match_datetime('2022-03-06 00:00:00')
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.subscription_kind.count).to eq(1)
              expect(result.invoice.fees.charge_kind.count).to eq(0)
            end
          end
        end
      end
    end

    context 'when billed weekly on first week' do
      let(:timestamp) { Time.zone.now.beginning_of_week }
      let(:started_at) { timestamp - 3.days }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_at: started_at.to_date,
          started_at: started_at,
          created_at: started_at,
        )
      end

      let(:plan) do
        create(:plan, interval: 'weekly')
      end

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_datetime'])
            .to match_datetime((timestamp - 1.day).end_of_day)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime(subscription.subscription_at.beginning_of_day)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when billed yearly' do
      let(:timestamp) { Time.zone.now.beginning_of_year }

      let(:plan) do
        create(:plan, interval: 'yearly', pay_in_advance: pay_in_advance)
      end

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_datetime'])
            .to match_datetime((timestamp - 1.day).end_of_day)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime((timestamp - 1.year).beginning_of_day)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Jun 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2020').to_date }
        let(:subscription_at) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_at: subscription_at,
            started_at: started_at,
            billing_time: :anniversary,
            created_at: started_at,
          )
        end

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.fees.first.properties['to_datetime']).to match_datetime('2022-06-05 23:59:59')
            expect(result.invoice.fees.first.properties['from_datetime']).to match_datetime('2021-06-06 00:00:00')
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
            expect(result.invoice.fees.charge_kind.count).to eq(1)
          end
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'updates the invoice accordingly' do
            result = invoice_service.call

            aggregate_failures do
              expect(result).to be_success

              expect(result.invoice.fees.first.properties['to_datetime']).to match_datetime('2023-06-05 23:59:59')
              expect(result.invoice.fees.first.properties['from_datetime']).to match_datetime('2022-06-06 00:00:00')
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.subscription_kind.count).to eq(1)
              expect(result.invoice.fees.charge_kind.count).to eq(0)
            end
          end
        end
      end
    end

    context 'when billed yearly on first year' do
      let(:plan) do
        create(:plan, interval: 'yearly')
      end

      let(:timestamp) { Time.zone.now.end_of_year + 1.day }
      let(:started_at) { Time.zone.today - 3.months }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_at: started_at.to_date,
          started_at: started_at,
          created_at: started_at,
        )
      end

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_datetime']).to match_datetime((timestamp - 1.day).end_of_day)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime(subscription.subscription_at.beginning_of_day)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
        end
      end
    end

    context 'when subscription is terminated and plan is pay in arrear' do
      let(:plan) do
        create(:plan, interval: 'monthly', pay_in_advance: false)
      end

      let(:timestamp) { Time.zone.now.beginning_of_month - 1.day }
      let(:started_at) { Time.zone.today - 3.months }
      let(:terminated_at) { timestamp - 2.days }
      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_at: started_at.to_date,
          started_at: started_at,
          status: :terminated,
          terminated_at: terminated_at,
          created_at: started_at,
        )
      end

      it 'updates the invoice with subscription fee' do
        result = invoice_service.call

        aggregate_failures do
          expect(result.invoice.fees.first.properties['to_datetime'])
            .to match_datetime(terminated_at)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime(terminated_at.beginning_of_month)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
        end
      end

      context 'when subscription is billed on anniversary date' do
        let(:timestamp) { DateTime.parse('07 Mar 2022') }
        let(:started_at) { DateTime.parse('06 Jun 2021').to_date }
        let(:subscription_at) { started_at }

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            subscription_at: subscription_at,
            started_at: started_at,
            status: :terminated,
            billing_time: :anniversary,
            terminated_at: terminated_at,
            created_at: started_at,
          )
        end

        it 'updates the invoice with subscription fee' do
          result = invoice_service.call

          aggregate_failures do
            expect(result.invoice.fees.first.properties['to_datetime'])
              .to match_datetime(terminated_at)
            expect(result.invoice.fees.first.properties['from_datetime'])
              .to match_datetime('2022-03-06 00:00:00')
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
          end
        end
      end
    end

    context 'when subscription is pay in advance and is an upgrade' do
      let(:plan) do
        create(:plan, interval: :monthly, pay_in_advance: true, amount_cents: 1000)
      end

      let(:timestamp) { Time.zone.parse('30 Sep 2022 00:31:00') }
      let(:started_at) { Time.zone.parse('12 Aug 2022 00:31:00') }
      let(:terminated_at) { timestamp - 2.days }
      let(:previous_plan) { create(:plan, amount_cents: 10_000, interval: :yearly, pay_in_advance: true) }

      let(:previous_subscription) do
        create(
          :subscription,
          plan: previous_plan,
          subscription_at: started_at.to_date,
          started_at: started_at,
          status: :terminated,
          terminated_at: terminated_at,
        )
      end

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          previous_subscription: previous_subscription,
          subscription_at: started_at.to_date,
          started_at: terminated_at + 1.day,
          created_at: terminated_at + 1.day,
        )
      end

      before { subscription }

      it 'creates an invoice with pro-rated charge fee and without charge fees' do
        result = invoice_service.call

        aggregate_failures do
          expect(result.invoice.fees.first.properties['to_datetime'])
            .to match_datetime(subscription.started_at.end_of_month)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime(subscription.started_at)
          expect(result.invoice.total_amount_cents).to eq(81)
          expect(result.invoice).to be_pending
          expect(result.invoice.fees.charge_kind.count).to eq(0)
        end
      end
    end

    context 'when subscription is pay in advance and terminated after upgrade' do
      let(:plan) do
        create(:plan, interval: :monthly, pay_in_advance: true, amount_cents: 1000)
      end
      let(:next_subscription) do
        create(
          :subscription,
          plan: next_plan,
          subscription_at: started_at.to_date,
          started_at: terminated_at,
          status: :active,
          billing_time: :calendar,
          previous_subscription: subscription,
          customer: subscription.customer,
        )
      end

      let(:started_at) { DateTime.parse('07 Mar 2022') }
      let(:terminated_at) { DateTime.parse('17 Oct 2022 12:35:12') }
      let(:timestamp) { DateTime.parse('17 Oct 2022') }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_at: started_at.to_date,
          started_at: started_at,
          status: :terminated,
          terminated_at: terminated_at,
          billing_time: :calendar,
        )
      end

      let(:next_plan) { create(:plan, interval: :monthly, amount_cents: 2000) }

      let(:charge) do
        create(:standard_charge, plan: plan, properties: { amount: 100 })
      end

      before { next_subscription }

      it 'updates the invoice with only the charge fees' do
        result = invoice_service.call

        aggregate_failures do
          expect(result.invoice.fees.subscription_kind.count).to eq(0)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          charge_fee = result.invoice.fees.charge_kind.first
          expect(charge_fee.properties['charges_from_datetime']).to match_datetime('2022-10-01 00:00:00')
          expect(charge_fee.properties['charges_to_datetime']).to match_datetime(terminated_at)
        end
      end
    end

    context 'with credit' do
      let(:credit_note) do
        create(
          :credit_note,
          customer: subscription.customer,
          total_amount_cents: 10,
          total_amount_currency: plan.amount_currency,
          balance_amount_cents: 10,
          balance_amount_currency: plan.amount_currency,
          credit_amount_cents: 10,
          credit_amount_currency: plan.amount_currency,
        )
      end

      before { credit_note }

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.credit_amount_cents).to eq(10)
          expect(result.invoice.total_amount_cents).to eq(110)
          expect(result.invoice.credits.count).to eq(1)

          credit = result.invoice.credits.first
          expect(credit.credit_note).to eq(credit_note)
          expect(credit.amount_cents).to eq(10)
        end
      end
    end

    context 'with applied coupons' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:applied_coupon) do
        create(
          :applied_coupon,
          customer: subscription.customer,
          amount_cents: 10,
          amount_currency: plan.amount_currency,
        )
      end
      let(:coupon_latest) { create(:coupon, coupon_type: 'percentage') }
      let(:applied_coupon_latest) do
        create(
          :applied_coupon,
          coupon: coupon_latest,
          customer: subscription.customer,
          percentage_rate: 20.00,
          created_at: applied_coupon.created_at + 1.day,
        )
      end

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      before do
        applied_coupon
        applied_coupon_latest
      end

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_datetime'])
            .to match_datetime((timestamp - 1.day).end_of_day)
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to match_datetime((timestamp - 1.month).beginning_of_day)
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)

          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.credit_amount_cents).to eq(32)
          expect(result.invoice.total_amount_cents).to eq(88)

          expect(result.invoice.credits.count).to eq(2)
        end
      end

      context 'when both coupons are fixed amount' do
        let(:coupon_latest) { create(:coupon, coupon_type: 'fixed_amount') }
        let(:applied_coupon_latest) do
          create(
            :applied_coupon,
            coupon: coupon_latest,
            customer: subscription.customer,
            amount_cents: 20,
            amount_currency: plan.amount_currency,
            created_at: applied_coupon.created_at + 1.day,
          )
        end

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.fees.first.properties['to_datetime'])
              .to match_datetime((timestamp - 1.day).end_of_day)
            expect(result.invoice.fees.first.properties['from_datetime'])
              .to match_datetime((timestamp - 1.month).beginning_of_day)
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.issuing_date.to_date).to eq(timestamp)
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
            expect(result.invoice.fees.charge_kind.count).to eq(1)

            expect(result.invoice.amount_cents).to eq(100)
            expect(result.invoice.vat_amount_cents).to eq(20)
            expect(result.invoice.total_amount_cents).to eq(90)

            expect(result.invoice.credits.count).to eq(2)
          end
        end
      end

      context 'when both coupons are percentage' do
        let(:coupon) { create(:coupon, coupon_type: 'percentage') }
        let(:applied_coupon) do
          create(
            :applied_coupon,
            coupon: coupon,
            customer: subscription.customer,
            percentage_rate: 15.00,
          )
        end

        it 'updates the invoice accordingly' do
          result = invoice_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(result.invoice.fees.first.properties['to_datetime'])
              .to match_datetime((timestamp - 1.day).end_of_day)
            expect(result.invoice.fees.first.properties['from_datetime'])
              .to match_datetime((timestamp - 1.month).beginning_of_day)
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.issuing_date.to_date).to eq(timestamp)
            expect(result.invoice.fees.subscription_kind.count).to eq(1)
            expect(result.invoice.fees.charge_kind.count).to eq(1)

            expect(result.invoice.amount_cents).to eq(100)
            expect(result.invoice.vat_amount_cents).to eq(20)
            expect(result.invoice.total_amount_cents).to eq(82)

            expect(result.invoice.credits.count).to eq(2)
          end
        end
      end

      context 'when coupon has a difference currency' do
        let(:applied_coupon) do
          create(
            :applied_coupon,
            customer: subscription.customer,
            amount_cents: 10,
            amount_currency: 'NOK',
          )
        end

        before { applied_coupon_latest.update!(status: :terminated) }

        it 'ignore the coupon' do
          result = invoice_service.call

          expect(result).to be_success
          expect(result.invoice.credits.count).to be_zero
        end
      end
    end

    context 'with applied prepaid credits' do
      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:wallet) { create(:wallet, customer: subscription.customer, balance: '0.30', credits_balance: '0.30') }

      let(:plan) do
        create(:plan, interval: 'monthly')
      end

      before { wallet }

      it 'updates the invoice accordingly' do
        result = invoice_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.fees.first.properties['to_datetime'])
            .to eq (timestamp - 1.day).end_of_day.as_json
          expect(result.invoice.fees.first.properties['from_datetime'])
            .to eq (timestamp - 1.month).beginning_of_day.as_json
          expect(result.invoice.subscriptions.first).to eq(subscription)
          expect(result.invoice.fees.subscription_kind.count).to eq(1)
          expect(result.invoice.fees.charge_kind.count).to eq(1)
          expect(result.invoice.amount_cents).to eq(100)
          expect(result.invoice.vat_amount_cents).to eq(20)
          expect(result.invoice.credit_amount_cents).to eq(30)
          expect(result.invoice.total_amount_cents).to eq(90)
          expect(result.invoice.wallet_transactions.count).to eq(1)
        end
      end

      it 'updates wallet balance' do
        invoice_service.call

        expect(wallet.reload.balance).to eq(0.0)
      end

      context 'when invoice amount in cents is zero' do
        let(:applied_coupon) do
          create(
            :applied_coupon,
            customer: subscription.customer,
            amount_cents: 120,
            amount_currency: plan.amount_currency,
          )
        end

        before { applied_coupon }

        it 'does not create any wallet transactions' do
          result = invoice_service.call

          expect(result.invoice.wallet_transactions.exists?).to be(false)
        end
      end
    end
  end
end
