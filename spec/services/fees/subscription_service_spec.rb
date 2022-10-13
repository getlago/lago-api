# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::SubscriptionService do
  subject(:fees_subscription_service) do
    described_class.new(
      invoice: invoice,
      subscription: subscription,
      boundaries: boundaries,
    )
  end

  let(:started_at) { Time.zone.parse('2022-01-01 00:01') }
  let(:created_at) { started_at }
  let(:subscription_date) { started_at }

  let(:plan) do
    create(
      :plan,
      amount_cents: 100,
      amount_currency: 'EUR',
    )
  end
  let(:invoice) { create(:invoice) }
  let(:boundaries) do
    {
      from_date: Time.zone.parse('2022-03-01 00:00').to_date,
      to_date: Time.zone.parse('2022-03-01 00:00').end_of_month.to_date,
      timestamp: Time.zone.parse('2022-04-02 00:00').end_of_month.to_i,
    }
  end

  let(:customer) { create(:customer) }

  let(:subscription) do
    create(
      :subscription,
      plan: plan,
      started_at: started_at,
      subscription_date: subscription_date,
      customer: customer,
      created_at: created_at,
      external_id: 'sub_id',
    )
  end

  context 'when invoice is on a full period' do
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
        expect(created_fee.units).to eq(1)
        expect(created_fee.events_count).to be_nil
      end
    end

    context 'when plan has a trial period' do
      before do
        plan.update(trial_period: trial_duration)
        subscription.update(started_at: boundaries[:from_date])
      end

      context 'when trial end in period' do
        let(:trial_duration) { 3 }

        it 'creates a fee with prorated amount based on trial' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.amount_cents).to eq(90)
          end
        end
      end

      context 'when trial end after end of period' do
        let(:trial_duration) { 45 }

        it 'creates a fee with zero amount' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(0)
        end
      end
    end
  end

  context 'when subscription has never been billed' do
    let(:boundaries) do
      {
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.end_of_month.to_date,
        timestamp: (subscription.started_at.end_of_month + 1.day).to_i,
      }
    end

    context 'when plan is weekly' do
      let(:boundaries) do
        {
          from_date: subscription.started_at.to_date,
          to_date: subscription.started_at.end_of_week.to_date,
          timestamp: (subscription.started_at.end_of_week + 1.day).to_i,
        }
      end

      before do
        plan.weekly!
      end

      context 'when subscription start is on Monday' do
        let(:started_at) { Time.zone.parse('2022-06-20 00:01') }

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
            expect(created_fee.units).to eq(1)
          end
        end

        context 'when plan has a trial period' do
          before { plan.update(trial_period: trial_duration) }

          context 'when trial end during period' do
            let(:trial_duration) { 3 }

            it 'creates a fee with prorated amount based on trial' do
              result = fees_subscription_service.create
              created_fee = result.fee

              # 100 - ((100/7)*3)
              expect(created_fee.amount_cents).to eq(57)
            end
          end

          context 'when trial end after end of period' do
            let(:trial_duration) { 10 }

            it 'creates a fee with zero amount' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(0)
            end
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            expect(created_fee.amount_cents).to eq(100)
          end

          context 'when plan has a trial period' do
            before { plan.update(trial_period: trial_duration) }

            context 'when trial end in period' do
              let(:trial_duration) { 3 }

              it 'creates a fee with prorated amount based on trial' do
                result = fees_subscription_service.create
                created_fee = result.fee

                expect(created_fee.amount_cents).to eq(57)
              end
            end

            context 'when trial end after period' do
              let(:trial_duration) { 10 }

              it 'creates a fee with zero amount' do
                result = fees_subscription_service.create
                created_fee = result.fee

                expect(created_fee.amount_cents).to eq(0)
              end
            end
          end
        end
      end

      context 'when subscription start is on any other day' do
        let(:started_at) { Time.zone.parse('2022-06-22 00:00') }

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(71)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(15)
            expect(created_fee.vat_rate).to eq(20.0)
            expect(created_fee.units).to eq(1)
          end
        end

        context 'when plan has a trial period' do
          before { plan.update(trial_period: trial_duration) }

          context 'when trial end during the period' do
            let(:trial_duration) { 3 }

            it 'creates a fee with prorated amount based on trial' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(29)
            end
          end

          context 'when trial end after the period end' do
            let(:trial_duration) { 10 }

            it 'creates a fee with zero amount' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(0)
            end
          end
        end

        context 'when plan is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(71)
            end
          end

          context 'when plan has a trial period' do
            before { plan.update(trial_period: trial_duration) }

            context 'when trial end during the period' do
              let(:trial_duration) { 3 }

              it 'creates a fee with prorated amount based on trial' do
                result = fees_subscription_service.create

                expect(result.fee.amount_cents).to eq(29)
              end
            end

            context 'when trial end after the period end' do
              let(:trial_duration) { 10 }

              it 'creates a fee with zero amount' do
                result = fees_subscription_service.create

                expect(result.fee.amount_cents).to eq(0)
              end
            end
          end
        end

        context 'when subscription is created in the past' do
          context 'when plan is pay in advance' do
            let(:created_at) { subscription_date + 2.days }

            before { plan.update(pay_in_advance: true) }

            it 'creates a full amount fee' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(plan.amount_cents)
            end
          end

          context 'when subscription has started before previous billing period' do
            let(:created_at) { subscription_date + 8.days }

            let(:boundaries) do
              {
                from_date: subscription.created_at.beginning_of_week.to_date,
                to_date: subscription.created_at.end_of_week.to_date,
                timestamp: (subscription.created_at.end_of_week + 1.day).to_i,
              }
            end

            it 'creates a full amount fee' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(plan.amount_cents)
            end
          end
        end
      end
    end

    context 'when plan is monthly' do
      before { plan.monthly! }

      context 'when subscription start is on the 1st of the month' do
        let(:started_at) { Time.zone.parse('2022-01-01 00:01') }

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
            expect(created_fee.units).to eq(1)
          end
        end

        context 'when plan has a trial period' do
          before { plan.update(trial_period: trial_duration) }

          context 'when trial end during period' do
            let(:trial_duration) { 3 }

            it 'creates a fee with prorated amount based on trial' do
              result = fees_subscription_service.create
              created_fee = result.fee

              expect(created_fee.amount_cents).to eq(90)
            end
          end

          context 'when trial end after end of period' do
            let(:trial_duration) { 45 }

            it 'creates a fee with zero amount' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(0)
            end
          end
        end

        context 'when plan is pay in advance' do
          let(:boundaries) do
            {
              from_date: subscription.started_at.to_date,
              to_date: subscription.started_at.end_of_month.to_date,
              timestamp: (subscription.started_at + 1.day).to_i,
            }
          end

          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            expect(created_fee.amount_cents).to eq(100)
          end

          context 'when plan has a trial period' do
            before { plan.update(trial_period: trial_duration) }

            context 'when trial end in period' do
              let(:trial_duration) { 3 }

              it 'creates a fee with prorated amount based on trial' do
                result = fees_subscription_service.create
                created_fee = result.fee

                expect(created_fee.amount_cents).to eq(90)
              end
            end

            context 'when trial end after period' do
              let(:trial_duration) { 45 }

              it 'creates a fee with zero amount' do
                result = fees_subscription_service.create
                created_fee = result.fee

                expect(created_fee.amount_cents).to eq(0)
              end
            end
          end
        end
      end

      context 'when subscription start is on any other day' do
        let(:started_at) { Time.zone.parse('2022-03-15 00:00:00') }

        it 'creates a fee' do
          result = fees_subscription_service.create
          created_fee = result.fee

          aggregate_failures do
            expect(created_fee.id).not_to be_nil
            expect(created_fee.invoice_id).to eq(invoice.id)
            expect(created_fee.amount_cents).to eq(55)
            expect(created_fee.amount_currency).to eq(plan.amount_currency)
            expect(created_fee.vat_amount_cents).to eq(11)
            expect(created_fee.vat_rate).to eq(20.0)
            expect(created_fee.units).to eq(1)
          end
        end

        context 'when plan has a trial period' do
          before { plan.update(trial_period: trial_duration) }

          context 'when trial end during the period' do
            let(:trial_duration) { 3 }

            it 'creates a fee with prorated amount based on trial' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(45)
            end
          end

          context 'when trial end after the period end' do
            let(:trial_duration) { 45 }

            it 'creates a fee with zero amount' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(0)
            end
          end
        end

        context 'when plan is pay in advance' do
          let(:boundaries) do
            {
              from_date: subscription.started_at.to_date,
              to_date: subscription.started_at.end_of_month.to_date,
              timestamp: (subscription.started_at + 1.day).to_i,
            }
          end

          before { plan.update(pay_in_advance: true) }

          it 'creates a fee' do
            result = fees_subscription_service.create
            created_fee = result.fee

            aggregate_failures do
              expect(created_fee.amount_cents).to eq(55)
            end
          end

          context 'when plan has a trial period' do
            before { plan.update(trial_period: trial_duration) }

            context 'when trial end during the period' do
              let(:trial_duration) { 3 }

              it 'creates a fee with prorated amount based on trial' do
                result = fees_subscription_service.create

                expect(result.fee.amount_cents).to eq(45)
              end
            end

            context 'when trial end after the period end' do
              let(:trial_duration) { 45 }

              it 'creates a fee with zero amount' do
                result = fees_subscription_service.create

                expect(result.fee.amount_cents).to eq(0)
              end
            end
          end
        end
      end

      context 'when subscription is based on anniversary date' do
        let(:started_at) { Time.zone.parse('2022-08-31 00:01') }

        let(:plan) do
          create(
            :plan,
            amount_cents: 3000,
            amount_currency: 'EUR',
          )
        end

        let(:subscription) do
          create(
            :subscription,
            plan: plan,
            started_at: started_at,
            subscription_date: DateTime.parse('2022-08-31'),
            billing_time: :anniversary,
            customer: customer,
            external_id: 'sub_id',
          )
        end

        let(:boundaries) do
          {
            from_date: Time.zone.parse('2022-08-31 00:00').to_date,
            to_date: Time.zone.parse('2022-09-30 00:00').to_date,
            timestamp: Time.zone.parse('2022-04-02 00:00').end_of_month.to_i,
          }
        end

        context 'when subscription is pay in advance' do
          before { plan.update(pay_in_advance: true) }

          context 'when plan has a trial period' do
            before { plan.update(trial_period: 15) }

            it 'creates a fee with prorated amount based on trial' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(1548)
            end
          end
        end
      end
    end

    context 'when plan is yearly' do
      before { plan.yearly! }

      context 'when subscription start is on the 1st day of the year' do
        let(:started_at) { Time.zone.now.beginning_of_year }

        let(:boundaries) do
          {
            from_date: subscription.started_at.beginning_of_year.to_date,
            to_date: subscription.started_at.end_of_year.to_date,
            timestamp: (subscription.started_at.end_of_year + 1.day).to_i,
          }
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
        let(:started_at) { Time.zone.parse('2022-03-15 00:00:00') }

        let(:boundaries) do
          {
            from_date: subscription.started_at.to_date,
            to_date: subscription.started_at.end_of_year.to_date,
            timestamp: (subscription.started_at.end_of_year + 1.day).to_i,
          }
        end

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
    let(:started_at) { Time.zone.parse('2022-01-01 00:00') }

    let(:boundaries) do
      {
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.end_of_month.to_date,
        timestamp: (subscription.started_at.end_of_month + 1.day).to_i,
      }
    end

    let(:invoice) do
      create(
        :invoice,
        issuing_date: subscription.started_at.end_of_month.to_date + 1.day,
      )
    end

    before do
      other_invoice = create(:invoice)
      create(:fee, subscription: subscription, invoice: other_invoice)
    end

    it 'creates a fee with full period amount' do
      result = fees_subscription_service.create
      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.amount_cents).to eq(100)
      end
    end

    context 'when plan has trial period' do
      context 'when trial end during period' do
        before { plan.update(trial_period: 3) }

        it 'creates a fee with prorated amount on trial period' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(90)
        end

        context 'when plan is pay in advance' do
          before do
            plan.update!(
              pay_in_advance: true,
              trial_period: trial_period,
              interval: interval,
            )
          end

          context 'when plan is weekly' do
            let(:boundaries) do
              {
                from_date: subscription.started_at.to_date.end_of_week,
                to_date: (subscription.started_at.end_of_week + 1.week).to_date,
                timestamp: (subscription.started_at.end_of_week + 1.day).to_i,
              }
            end

            let(:interval) { :weekly }
            let(:trial_period) { 5 }

            it 'creates a fee with prorated amount on trial period' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(57)
            end
          end

          context 'when plan is monthly' do
            let(:interval) { :monthly }
            let(:trial_period) { 15 }

            let(:boundaries) do
              {
                from_date: subscription.started_at.to_date,
                to_date: subscription.started_at.end_of_month.to_date,
                timestamp: (subscription.started_at + 1.day).to_i,
              }
            end

            it 'creates a fee with prorated amount on trial period' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(52)
            end
          end

          context 'when plan is yearly' do
            let(:boundaries) do
              {
                from_date: subscription.started_at.to_date.beginning_of_year,
                to_date: subscription.started_at.end_of_year.to_date,
                timestamp: (subscription.started_at.beginning_of_year + 1.day).to_i,
              }
            end

            let(:interval) { :yearly }
            let(:trial_period) { 35 }

            it 'creates a fee with prorated amount on trial period' do
              result = fees_subscription_service.create

              expect(result.fee.amount_cents).to eq(90)
            end
          end
        end
      end

      context 'when trial end after period' do
        before { plan.update(trial_period: 45) }

        it 'creates a fee with 0 amount' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(0)
        end
      end
    end
  end

  context 'when already billed fee' do
    let(:plan) do
      create(
        :plan,
        amount_cents: 100,
        amount_currency: 'EUR',
      )
    end

    let(:started_at) { Time.zone.parse('2022-01-01 00:00:00') }

    let(:boundaries) do
      {
        from_date: subscription.started_at + 1.month,
        to_date: subscription.started_at + 2.months,
        timestamp: (subscription.started_at + 2.months + 1.day).to_i,
      }
    end

    before do
      create(:fee, subscription: subscription, invoice: invoice)
    end

    it 'does not create a fee' do
      expect { fees_subscription_service.create }.not_to change(Fee, :count)
    end
  end

  context 'when billing a newly terminated subscription' do
    let(:started_at) { Time.zone.parse('2022-03-15 00:00:00') }

    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        status: :terminated,
        started_at: started_at,
        subscription_date: subscription_date,
        customer: customer,
        external_id: 'sub_id',
      )
    end

    let(:boundaries) do
      {
        from_date: subscription.started_at.beginning_of_month.to_date,
        to_date: subscription.started_at.to_date + 5.days,
        timestamp: (subscription.started_at + 6.days).to_i,
      }
    end

    before do
      plan.update!(pay_in_advance: false)
    end

    it 'creates a fee' do
      result = fees_subscription_service.create
      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.id).not_to be_nil
        expect(created_fee.invoice_id).to eq(invoice.id)
        expect(created_fee.amount_cents).to eq(65)
        expect(created_fee.amount_currency).to eq(plan.amount_currency)
        expect(created_fee.vat_amount_cents).to eq(13)
        expect(created_fee.vat_rate).to eq(20.0)
      end
    end

    context 'when plan is weekly' do
      let(:boundaries) do
        {
          from_date: subscription.started_at.beginning_of_week.to_date,
          to_date: subscription.started_at.to_date + 1.day,
          timestamp: (subscription.started_at + 2.days).to_i,
        }
      end

      before do
        plan.weekly!
      end

      it 'creates a fee' do
        result = fees_subscription_service.create
        created_fee = result.fee

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.amount_cents).to eq(43)
          expect(created_fee.amount_currency).to eq(plan.amount_currency)
          expect(created_fee.vat_amount_cents).to eq(9)
          expect(created_fee.vat_rate).to eq(20.0)
        end
      end
    end

    context 'with a next subscription' do
      before do
        create(:subscription, previous_subscription: subscription)
      end

      it 'creates a fee' do
        result = fees_subscription_service.create
        created_fee = result.fee

        aggregate_failures do
          expect(created_fee.id).not_to be_nil
          expect(created_fee.invoice_id).to eq(invoice.id)
          expect(created_fee.amount_cents).to eq(65)
          expect(created_fee.amount_currency).to eq(plan.amount_currency)
          expect(created_fee.vat_amount_cents).to eq(13)
          expect(created_fee.vat_rate).to eq(20.0)
        end
      end
    end

    context 'when plan has trial period' do
      before do
        plan.update(trial_period: trial_duration)
        create(:subscription, previous_subscription: subscription)
      end

      context 'when trial end before termination date' do
        let(:trial_duration) { 3 }

        it 'creates a fee with prorated amount based on trial period' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(10)
        end
      end

      context 'when trial end after termination date' do
        let(:trial_duration) { 45 }

        it 'creates a fee with zero amount' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(0)
        end
      end
    end
  end

  context 'when billing a new upgraded subscription' do
    let(:previous_plan) { create(:plan, pay_in_advance: true, amount_cents: 80) }
    let(:previous_subscription) do
      create(
        :subscription,
        status: :terminated,
        plan: previous_plan,
        started_at: started_at - 6.months,
        customer: customer,
        external_id: 'sub_id',
      )
    end
    let(:started_at) { Time.zone.parse('2022-03-15 00:00:00') }

    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        started_at: started_at,
        subscription_date: subscription_date,
        previous_subscription: previous_subscription,
        customer: customer,
        external_id: 'sub_id',
      )
    end

    let(:boundaries) do
      {
        from_date: subscription.started_at.to_date,
        to_date: subscription.started_at.to_date.end_of_month,
        timestamp: (subscription.started_at.end_of_month + 1.day).to_i,
      }
    end

    before { previous_plan.update!(pay_in_advance: false) }

    it 'creates a subscription fee' do
      result = fees_subscription_service.create
      created_fee = result.fee

      aggregate_failures do
        expect(created_fee.id).not_to be_nil
        expect(created_fee.invoice_id).to eq(invoice.id)
        expect(created_fee.amount_cents).to eq(55)
        expect(created_fee.amount_currency).to eq(plan.amount_currency)
        expect(created_fee.vat_amount_cents).to eq(11)
        expect(created_fee.vat_rate).to eq(20.0)
      end
    end

    context 'when plan has trial period' do
      before { plan.update(trial_period: trial_duration) }

      context 'when trial period end before period end' do
        let(:trial_duration) { (subscription.started_at.to_date - previous_subscription.started_at.to_date).to_i + 3 }

        it 'creates a fee with prorated amount based on the trial' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(45)
        end
      end

      context 'when trial period end after period end' do
        let(:trial_duration) do
          (subscription.started_at.to_date - previous_subscription.started_at.to_date).to_i + 45
        end

        it 'creates a fee with zero amount' do
          result = fees_subscription_service.create

          expect(result.fee.amount_cents).to eq(0)
        end
      end
    end

    context 'when new plan is pay in advance' do
      before do
        plan.update(pay_in_advance: true)
        subscription.previous_subscription.update(terminated_at: subscription.started_at)
      end

      let(:boundaries) do
        {
          from_date: subscription.started_at.to_date,
          to_date: subscription.started_at.end_of_month.to_date,
          timestamp: subscription.started_at.to_i,
        }
      end

      it 'creates a subscription fee' do
        result = fees_subscription_service.create

        expect(result.fee.amount_cents).to eq(55)
      end
    end
  end
end
