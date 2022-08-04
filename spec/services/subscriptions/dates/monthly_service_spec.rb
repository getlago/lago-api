# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::Dates::MonthlyService, type: :service do
  subject(:date_service) { described_class.new(subscription, billing_date) }

  let(:subscription) do
    create(
      :subscription,
      plan: plan,
      subscription_date: subscription_date,
      billing_time: billing_time,
      started_at: started_at,
    )
  end

  let(:plan) { create(:plan, interval: :monthly, pay_in_advance: pay_in_advance) }
  let(:pay_in_advance) { false }

  let(:subscription_date) { DateTime.parse('02 Feb 2021') }
  let(:billing_date) { DateTime.parse('07 Mar 2022') }
  let(:started_at) { subscription_date }

  describe 'from_date' do
    let(:result) { date_service.from_date.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }
      let(:billing_date) { DateTime.parse('01 Mar 2022') }

      it 'returns the beginning of the previous month' do
        expect(result).to eq('2022-02-01')
      end

      context 'when date is before the start date' do
        let(:started_at) { DateTime.parse('07 Feb 2022') }

        it 'returns the start date' do
          expect(result).to eq(started_at.to_date.to_s)
        end
      end

      context 'when subscription is just terminated' do
        let(:billing_date) { DateTime.parse('10 Mar 2022') }

        before { subscription.terminated! }

        it 'returns the beginning of the month' do
          expect(result).to eq('2022-03-01')
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'returns the beginning of the previous month' do
            expect(result).to eq('2022-02-01')
          end
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_date) { DateTime.parse('03 Mar 2022') }

      it 'returns the previous month month day' do
        expect(result).to eq('2022-02-02')
      end

      context 'when date is before the start date' do
        let(:started_at) { DateTime.parse('08 Feb 2022') }

        it 'returns the start date' do
          expect(result).to eq(started_at.to_date.to_s)
        end
      end

      context 'when subscription is just terminated' do
        let(:billing_date) { DateTime.parse('10 Mar 2022') }

        before { subscription.terminated! }

        it 'returns the previous month day' do
          expect(result).to eq('2022-03-02')
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'returns the previous month month day' do
            expect(result).to eq('2022-02-02')
          end
        end

        context 'when billing day after last day of billing month' do
          let(:billing_date) { DateTime.parse('29 Mar 2022') }
          let(:subscription_date) { DateTime.parse('31 Mar 2021') }

          it 'returns the previous month last day' do
            expect(result).to eq('2022-02-28')
          end
        end

        context 'when billing day on first month of the year' do
          let(:billing_date) { DateTime.parse('28 Jan 2022') }
          let(:subscription_date) { DateTime.parse('29 Mar 2021') }

          it 'returns the previous month last day' do
            expect(result).to eq('2021-12-29')
          end
        end
      end
    end
  end

  describe 'to_date' do
    let(:result) { date_service.to_date.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }
      let(:billing_date) { DateTime.parse('01 Mar 2022') }

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

      context 'when subscription is just terminated' do
        let(:billing_date) { DateTime.parse('10 Mar 2022') }

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

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_date) { DateTime.parse('04 Mar 2022') }

      it 'returns the previous month month day' do
        expect(result).to eq('2022-03-01')
      end

      context 'when billing last month of year' do
        let(:billing_date) { DateTime.parse('04 Jan 2022') }

        it 'returns the previous month month day' do
          expect(result).to eq('2022-01-01')
        end
      end

      context 'when billing subscription day does not extist in the month' do
        let(:subscription_date) { DateTime.parse('31 Jan 2022') }
        let(:billing_date) { DateTime.parse('01 Mar 2022') }

        it 'returns the last day of the month' do
          expect(result).to eq('2022-02-28')
        end
      end

      context 'when anniversary date is first day of the month' do
        let(:subscription_date) { DateTime.parse('01 Jan 2022') }
        let(:billing_date) { DateTime.parse('02 Mar 2022') }

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

      context 'when subscription is just terminated' do
        let(:billing_date) { DateTime.parse('10 Mar 2022') }

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

  describe 'charges_from_date' do
    let(:result) { date_service.charges_from_date.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }
      let(:billing_date) { DateTime.parse('01 Mar 2022') }

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

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_date) { DateTime.parse('03 Mar 2022') }

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
  end

  describe 'next_end_of_period' do
    let(:result) { date_service.next_end_of_period(billing_date.to_date).to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns the last day of the month' do
        expect(result).to eq('2022-03-31')
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }

      it 'returns the end of the billing month' do
        expect(result).to eq('2022-04-01')
      end

      context 'when end of billing month is in next year' do
        let(:billing_date) { DateTime.parse('07 Dec 2021') }

        it { expect(result).to eq('2022-01-01') }
      end

      context 'when date is the end of the period' do
        let(:billing_date) { DateTime.parse('01 Mar 2022') }

        it 'returns the date' do
          expect(result).to eq(billing_date.to_date.to_s)
        end
      end
    end
  end
end
