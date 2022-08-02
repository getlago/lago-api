# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::DatesService, type: :service do
  subject(:date_service) { described_class.new(subscription, timestamp) }

  let(:subscription) do
    create(
      :subscription,
      plan: plan,
      subscription_date: subscription_date,
      billing_time: billing_time,
      started_at: started_at,
    )
  end

  let(:plan) { create(:plan, interval: interval, pay_in_advance: false) }

  let(:subscription_date) { DateTime.parse('02 Feb 2021') }
  let(:timestamp) { DateTime.parse('07 Mar 2022') }
  let(:started_at) { subscription_date }

  describe 'from_date' do
    let(:result) { date_service.from_date.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      context 'when interval is weekly' do
        let(:interval) { :weekly }

        it 'returns the beginning of the previous week' do
          expect(result).to eq('2022-02-28')
          expect(Time.zone.parse(result).wday).to eq(1)
        end

        context 'when date is before the start date' do
          let(:started_at) { DateTime.parse('01 Mar 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          let(:timestamp) { DateTime.parse('10 Mar 2022') }

          before { subscription.terminated! }

          it 'returns the beginning of the week' do
            expect(result).to eq('2022-03-07')
            expect(Time.zone.parse(result).wday).to eq(1)
          end
        end
      end

      context 'when interval is monthly' do
        let(:interval) { :monthly }
        let(:timestamp) { DateTime.parse('01 Mar 2022') }

        it 'returns the beginning of the previous month' do
          expect(result).to eq('2022-02-01')
        end

        context 'when date is before the start date' do
          let(:started_at) { DateTime.parse('07 Feb 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          let(:timestamp) { DateTime.parse('10 Mar 2022') }

          before { subscription.terminated! }

          it 'returns the beginning of the month' do
            expect(result).to eq('2022-03-01')
          end
        end
      end

      context 'when interval is yearly' do
        let(:interval) { :yearly }
        let(:timestamp) { DateTime.parse('01 Jan 2022') }
        let(:subscription_date) { DateTime.parse('02 Feb 2020') }

        it 'returns the beginning of the previous year' do
          expect(result).to eq('2021-01-01')
        end

        context 'when date is before the start date' do
          let(:started_at) { DateTime.parse('07 Feb 2021') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          let(:timestamp) { DateTime.parse('10 Mar 2022') }

          before { subscription.terminated! }

          it 'returns the beginning of the year' do
            expect(result).to eq('2022-01-01')
          end
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }

      context 'when interval is weekly' do
        let(:interval) { :weekly }
        let(:timestamp) { DateTime.parse('10 Mar 2022') }

        it 'returns the previous week week day' do
          expect(result).to eq('2022-03-01')
          expect(Time.zone.parse(result).wday).to eq(subscription_date.wday)
        end

        context 'when date is before the start date' do
          let(:started_at) { DateTime.parse('08 Mar 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
            expect(Time.zone.parse(result).wday).to eq(subscription_date.wday)
          end
        end

        context 'when subscription is terminated' do
          before { subscription.terminated! }

          it 'returns the previous week day' do
            expect(result).to eq('2022-03-08')
            expect(Time.zone.parse(result).wday).to eq(subscription_date.wday)
          end
        end
      end

      context 'when interval is monthly' do
        let(:interval) { :monthly }
        let(:timestamp) { DateTime.parse('03 Mar 2022') }

        it 'returns the previous month month day' do
          expect(result).to eq('2022-02-02')
        end

        context 'when date is before the start date' do
          let(:started_at) { DateTime.parse('08 Feb 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          let(:timestamp) { DateTime.parse('10 Mar 2022') }

          before { subscription.terminated! }

          it 'returns the previous month day' do
            expect(result).to eq('2022-03-02')
          end

          context 'when billing day after last day of billing month' do
            let(:timestamp) { DateTime.parse('29 Mar 2022') }
            let(:subscription_date) { DateTime.parse('31 Mar 2021') }

            it 'returns the previous month last day' do
              expect(result).to eq('2022-02-28')
            end
          end

          context 'when billing day on first month of the year' do
            let(:timestamp) { DateTime.parse('28 Jan 2022') }
            let(:subscription_date) { DateTime.parse('29 Mar 2021') }

            it 'returns the previous month last day' do
              expect(result).to eq('2021-12-29')
            end
          end
        end
      end

      context 'when interval is yearly' do
        let(:interval) { :yearly }
        let(:timestamp) { DateTime.parse('03 Feb 2022') }

        it 'returns the previous year day and month' do
          expect(result).to eq('2021-02-02')
        end

        context 'when date is before the start date' do
          let(:started_at) { DateTime.parse('02 Sep 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          before { subscription.terminated! }

          it 'returns the previous year day' do
            expect(result).to eq('2022-02-02')
          end

          context 'when subscription date on 29/02 of a leap year' do
            let(:subscription_date) { DateTime.parse('29 Feb 2020') }
            let(:timestamp) { DateTime.parse('01 Mar 2022') }

            it 'returns the previous month last day' do
              expect(result).to eq('2022-02-28')
            end
          end

          context 'when billing month is before subscription month' do
            let(:timestamp) { DateTime.parse('03 Jan 2022') }

            it 'returns the previous year day' do
              expect(result).to eq('2021-02-02')
            end
          end
        end
      end
    end
  end

  describe 'to_date' do
    let(:result) { date_service.to_date.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      context 'when interval is weekly' do
        let(:interval) { :weekly }
        let(:timestamp) { DateTime.parse('07 Mar 2022') }

        it 'returns the end of the previous week' do
          expect(result).to eq('2022-03-06')
        end

        context 'when plan is pay in advance and billed for the first time' do
          before { plan.update!(pay_in_advance: true) }

          let(:started_at) { DateTime.parse('15 Jun 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          let(:timestamp) { DateTime.parse('07 Mar 2022') }

          before do
            subscription.update!(
              status: :terminated,
              terminated_at: DateTime.parse('02 Mar 2022'),
            )
          end

          it 'returns the termination date' do
            expect(result).to eq(subscription.terminated_at.to_date.to_s)
          end

          context 'with next subscription' do
            let(:next_subscription) do
              create(:subscription, previous_subscription: subscription)
            end

            before { next_subscription }

            it 'returns the day before the termination date' do
              expect(result).to eq((subscription.terminated_at.to_date - 1.day).to_s)
            end
          end
        end
      end

      context 'when interval is monthly' do
        let(:interval) { :monthly }
        let(:timestamp) { DateTime.parse('01 Mar 2022') }

        it 'returns the end of the previous month' do
          expect(result).to eq('2022-02-28')
        end

        context 'when plan is pay in advance and billed for the first time' do
          before { plan.update!(pay_in_advance: true) }

          let(:started_at) { DateTime.parse('07 Feb 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          let(:timestamp) { DateTime.parse('10 Mar 2022') }

          before do
            subscription.update!(
              status: :terminated,
              terminated_at: DateTime.parse('02 Mar 2022'),
            )
          end

          it 'returns the termination date' do
            expect(result).to eq(subscription.terminated_at.to_date.to_s)
          end

          context 'with next subscription' do
            let(:next_subscription) do
              create(:subscription, previous_subscription: subscription)
            end

            before { next_subscription }

            it 'returns the day before the termination date' do
              expect(result).to eq((subscription.terminated_at.to_date - 1.day).to_s)
            end
          end
        end
      end

      context 'when interval is yearly' do
        let(:interval) { :yearly }
        let(:timestamp) { DateTime.parse('01 Jan 2022') }
        let(:subscription_date) { DateTime.parse('02 Feb 2020') }

        it 'returns the end of the previous year' do
          expect(result).to eq('2021-12-31')
        end

        context 'when plan is pay in advance and billed for the first time' do
          before { plan.update!(pay_in_advance: true) }

          let(:started_at) { DateTime.parse('07 Feb 2021') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          let(:timestamp) { DateTime.parse('10 Mar 2022') }

          before do
            subscription.update!(
              status: :terminated,
              terminated_at: DateTime.parse('02 Mar 2022'),
            )
          end

          it 'returns the termination date' do
            expect(result).to eq(subscription.terminated_at.to_date.to_s)
          end

          context 'with next subscription' do
            let(:next_subscription) do
              create(:subscription, previous_subscription: subscription)
            end

            before { next_subscription }

            it 'returns the day before the termination date' do
              expect(result).to eq((subscription.terminated_at.to_date - 1.day).to_s)
            end
          end
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }

      context 'when interval is weekly' do
        let(:interval) { :weekly }
        let(:timestamp) { DateTime.parse('10 Mar 2022') }

        it 'returns the previous week week day' do
          expect(result).to eq('2022-03-07')
        end

        context 'when plan is pay in advance and billed for the first time' do
          before { plan.update!(pay_in_advance: true) }

          let(:started_at) { DateTime.parse('08 Mar 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          before do
            subscription.update!(
              status: :terminated,
              terminated_at: DateTime.parse('02 Mar 2022'),
            )
          end

          it 'returns the termination date' do
            expect(result).to eq(subscription.terminated_at.to_date.to_s)
          end

          context 'with next subscription' do
            let(:next_subscription) do
              create(:subscription, previous_subscription: subscription)
            end

            before { next_subscription }

            it 'returns the day before the termination date' do
              expect(result).to eq((subscription.terminated_at.to_date - 1.day).to_s)
            end
          end
        end
      end

      context 'when interval is monthly' do
        let(:interval) { :monthly }
        let(:timestamp) { DateTime.parse('04 Mar 2022') }

        it 'returns the previous month month day' do
          expect(result).to eq('2022-03-01')
        end

        context 'when billing last month of year' do
          let(:timestamp) { DateTime.parse('04 Jan 2022') }

          it 'returns the previous month month day' do
            expect(result).to eq('2022-01-01')
          end
        end

        context 'when billing subscription day does not extist in the month' do
          let(:subscription_date) { DateTime.parse('31 Jan 2022') }
          let(:timestamp) { DateTime.parse('01 Mar 2022') }

          it 'returns the last day of the month' do
            expect(result).to eq('2022-02-28')
          end
        end

        context 'when anniversary date is first day of the month' do
          let(:subscription_date) { DateTime.parse('01 Jan 2022') }
          let(:timestamp) { DateTime.parse('02 Mar 2022') }

          it 'returns the last day of the month' do
            expect(result).to eq('2022-02-28')
          end
        end

        context 'when plan is pay in advance and billed for the first time' do
          before { plan.update!(pay_in_advance: true) }

          let(:started_at) { DateTime.parse('08 Feb 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          let(:timestamp) { DateTime.parse('10 Mar 2022') }

          before do
            subscription.update!(
              status: :terminated,
              terminated_at: DateTime.parse('02 Mar 2022'),
            )
          end

          it 'returns the termination date' do
            expect(result).to eq(subscription.terminated_at.to_date.to_s)
          end

          context 'with next subscription' do
            let(:next_subscription) do
              create(:subscription, previous_subscription: subscription)
            end

            before { next_subscription }

            it 'returns the day before the termination date' do
              expect(result).to eq((subscription.terminated_at.to_date - 1.day).to_s)
            end
          end
        end
      end

      context 'when interval is yearly' do
        let(:interval) { :yearly }
        let(:timestamp) { DateTime.parse('03 Feb 2022') }

        it 'returns the previous year day and month' do
          expect(result).to eq('2022-02-01')
        end

        context 'when subscription date on 29/02 of a leap year' do
          let(:subscription_date) { DateTime.parse('29 Feb 2020') }
          let(:timestamp) { DateTime.parse('01 Mar 2022') }

          it 'returns the previous month last day' do
            expect(result).to eq('2022-02-28')
          end
        end

        context 'when anniversary date is first day of the year' do
          let(:subscription_date) { DateTime.parse('01 Jan 2021') }
          let(:timestamp) { DateTime.parse('02 Mar 2022') }

          it 'returns the last day of the year' do
            expect(result).to eq('2021-12-31')
          end
        end

        context 'when plan is pay in advance and billed for the first time' do
          before { plan.update!(pay_in_advance: true) }

          let(:started_at) { DateTime.parse('02 Sep 2022') }

          it 'returns the start date' do
            expect(result).to eq(started_at.to_date.to_s)
          end
        end

        context 'when subscription is terminated' do
          before do
            subscription.update!(
              status: :terminated,
              terminated_at: DateTime.parse('02 Mar 2022'),
            )
          end

          it 'returns the termination date' do
            expect(result).to eq(subscription.terminated_at.to_date.to_s)
          end

          context 'with next subscription' do
            let(:next_subscription) do
              create(:subscription, previous_subscription: subscription)
            end

            before { next_subscription }

            it 'returns the day before the termination date' do
              expect(result).to eq((subscription.terminated_at.to_date - 1.day).to_s)
            end
          end
        end
      end
    end
  end

  describe 'charges_from_date' do
    let(:result) { date_service.charges_from_date.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      context 'when interval is weekly' do
        let(:interval) { :weekly }

        it 'returns from_date' do
          expect(result).to eq(date_service.from_date.to_s)
        end

        context 'when subscription is upgraded' do
          let(:previous_plan) do
            create(:plan, amount_cents: plan.amount_cents - 1)
          end

          let(:previous_subscription) do
            create(
              :subscription,
              plan: previous_plan,
              status: :terminated,
              terminated_at: started_at,
            )
          end

          let(:started_at) { DateTime.parse('03 Mar 2022') }

          before { subscription.update!(previous_subscription: previous_subscription) }

          it 'returns the beginning of the week' do
            expect(result).to eq('2022-02-28')
          end
        end
      end

      context 'when interval is monthly' do
        let(:interval) { :monthly }
        let(:timestamp) { DateTime.parse('01 Mar 2022') }

        it 'returns from_date' do
          expect(result).to eq(date_service.from_date.to_s)
        end

        context 'when subscription is upgraded' do
          let(:previous_plan) do
            create(:plan, amount_cents: plan.amount_cents - 1)
          end

          let(:previous_subscription) do
            create(
              :subscription,
              plan: previous_plan,
              status: :terminated,
              terminated_at: started_at,
            )
          end

          let(:started_at) { DateTime.parse('03 Mar 2022') }

          before { subscription.update!(previous_subscription: previous_subscription) }

          it 'returns the beginning of the month' do
            expect(result).to eq('2022-03-01')
          end
        end
      end

      context 'when interval is yearly' do
        let(:interval) { :yearly }
        let(:timestamp) { DateTime.parse('01 Jan 2022') }
        let(:subscription_date) { DateTime.parse('02 Feb 2020') }

        it 'returns from_date' do
          expect(result).to eq(date_service.from_date.to_s)
        end

        context 'when subscription is upgraded' do
          let(:previous_plan) do
            create(:plan, amount_cents: plan.amount_cents - 1, interval: plan.interval)
          end

          let(:previous_subscription) do
            create(
              :subscription,
              plan: previous_plan,
              status: :terminated,
              terminated_at: started_at,
            )
          end

          let(:timestamp) { DateTime.parse('07 Mar 2022') }
          let(:started_at) { DateTime.parse('03 Mar 2022') }

          before { subscription.update!(previous_subscription: previous_subscription) }

          it 'returns the beginning of the year' do
            expect(result).to eq('2022-01-01')
          end
        end

        context 'when billing charge monthly' do
          before { plan.update!(bill_charges_monthly: true) }

          it 'returns the begining of the previous month' do
            expect(result).to eq('2021-12-01')
          end

          context 'when subscription is upgraded' do
            let(:previous_plan) do
              create(
                :plan,
                amount_cents: plan.amount_cents - 1,
                interval: plan.interval,
                bill_charges_monthly: true,
              )
            end

            let(:previous_subscription) do
              create(
                :subscription,
                plan: previous_plan,
                status: :terminated,
                terminated_at: started_at,
              )
            end

            let(:timestamp) { DateTime.parse('07 Mar 2022') }
            let(:started_at) { DateTime.parse('03 Mar 2022') }

            before { subscription.update!(previous_subscription: previous_subscription) }

            it 'returns the beginning of the month' do
              expect(result).to eq('2022-03-01')
            end
          end
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }

      context 'when interval is weekly' do
        let(:interval) { :weekly }
        let(:timestamp) { DateTime.parse('10 Mar 2022') }

        it 'returns from_date' do
          expect(result).to eq(date_service.from_date.to_s)
        end

        context 'when subscription is upgraded' do
          let(:previous_plan) do
            create(:plan, amount_cents: plan.amount_cents - 1)
          end

          let(:previous_subscription) do
            create(
              :subscription,
              plan: previous_plan,
              status: :terminated,
              terminated_at: started_at,
            )
          end

          let(:started_at) { DateTime.parse('03 Mar 2022') }

          before { subscription.update!(previous_subscription: previous_subscription) }

          it 'returns the beginning of weekly period' do
            expect(result).to eq('2022-03-01')
          end
        end
      end

      context 'when interval is monthly' do
        let(:interval) { :monthly }
        let(:timestamp) { DateTime.parse('03 Mar 2022') }

        it 'returns from_date' do
          expect(result).to eq(date_service.from_date.to_s)
        end

        context 'when subscription is upgraded' do
          let(:previous_plan) do
            create(:plan, amount_cents: plan.amount_cents - 1)
          end

          let(:previous_subscription) do
            create(
              :subscription,
              plan: previous_plan,
              status: :terminated,
              terminated_at: started_at,
            )
          end

          let(:started_at) { DateTime.parse('03 Mar 2022') }

          before { subscription.update!(previous_subscription: previous_subscription) }

          it 'returns the beginning of the monthly period' do
            expect(result).to eq('2022-03-02')
          end
        end
      end

      context 'when interval is yearly' do
        let(:interval) { :yearly }
        let(:timestamp) { DateTime.parse('03 Feb 2022') }

        it 'returns from_date' do
          expect(result).to eq(date_service.from_date.to_s)
        end

        context 'when subscription is upgraded' do
          let(:previous_plan) do
            create(:plan, amount_cents: plan.amount_cents - 1, interval: plan.interval)
          end

          let(:previous_subscription) do
            create(
              :subscription,
              plan: previous_plan,
              status: :terminated,
              terminated_at: started_at,
            )
          end

          let(:timestamp) { DateTime.parse('07 Mar 2022') }
          let(:started_at) { DateTime.parse('03 Mar 2022') }

          before { subscription.update!(previous_subscription: previous_subscription) }

          it 'returns the beginning of the yearly period' do
            expect(result).to eq('2022-02-02')
          end
        end

        context 'when billing charge monthly' do
          before { plan.update!(bill_charges_monthly: true) }

          it 'returns the begining of the previous monthly period' do
            expect(result).to eq('2022-01-02')
          end

          context 'when subscription is upgraded' do
            let(:previous_plan) do
              create(
                :plan,
                amount_cents: plan.amount_cents - 1,
                interval: plan.interval,
                bill_charges_monthly: true,
              )
            end

            let(:previous_subscription) do
              create(
                :subscription,
                plan: previous_plan,
                status: :terminated,
                terminated_at: started_at,
              )
            end

            let(:timestamp) { DateTime.parse('07 Mar 2022') }
            let(:started_at) { DateTime.parse('03 Mar 2022') }

            before { subscription.update!(previous_subscription: previous_subscription) }

            it 'returns the beginning of the monthly period' do
              expect(result).to eq('2022-03-02')
            end
          end
        end
      end
    end
  end
end
