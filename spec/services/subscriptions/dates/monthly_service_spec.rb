# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::Dates::MonthlyService, type: :service do
  subject(:date_service) { described_class.new(subscription, billing_date, false) }

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

          it 'returns the beginning of the month' do
            expect(result).to eq('2022-03-01')
          end
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_date) { DateTime.parse('02 Mar 2022') }

      it 'returns the day in the previous month day' do
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

          it 'returns the day in the current month' do
            expect(result).to eq('2022-03-02')
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

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }

        it 'returns the end of the month' do
          expect(result).to eq('2022-03-31')
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
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_date) { DateTime.parse('02 Mar 2022') }

      it 'returns the day in the previous month' do
        expect(result).to eq('2022-03-01')
      end

      context 'when billing last month of year' do
        let(:billing_date) { DateTime.parse('04 Jan 2022') }

        it 'returns the day in the previous month' do
          expect(result).to eq('2022-01-01')
        end
      end

      context 'when billing subscription day does not exist in the month' do
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

      context 'when plan is pay in advance' do
        before { plan.update!(pay_in_advance: true) }

        it 'returns the end of the current period' do
          expect(result).to eq('2022-04-01')
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

      context 'when subscription started in the middle of a period' do
        let(:started_at) { DateTime.parse('03 Mar 2022') }

        it 'returns the start date' do
          expect(result).to eq(subscription.started_at.to_date.to_s)
        end
      end

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }
        let(:subscription_date) { DateTime.parse('02 Feb 2020') }

        it 'returns the start of the previous period' do
          expect(result).to eq('2022-02-01')
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_date) { DateTime.parse('02 Mar 2022') }

      it 'returns from_date' do
        expect(result).to eq(date_service.from_date.to_s)
      end

      context 'when subscription started in the middle of a period' do
        let(:started_at) { DateTime.parse('03 Mar 2022') }

        it 'returns the start date' do
          expect(result).to eq(subscription.started_at.to_date.to_s)
        end
      end

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }
        let(:subscription_date) { DateTime.parse('02 Feb 2020') }

        it 'returns the start of the previous period' do
          expect(result).to eq('2022-02-02')
        end
      end
    end
  end

  describe 'charges_to_date' do
    let(:result) { date_service.charges_to_date.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns to_date' do
        expect(result).to eq(date_service.to_date.to_s)
      end

      context 'when subscription is terminated in the middle of a period' do
        let(:terminated_at) { DateTime.parse('06 Mar 2022') }

        before do
          subscription.update!(status: :terminated, terminated_at: terminated_at)
        end

        it 'returns the terminated date' do
          expect(result).to eq(subscription.terminated_at.to_date.to_s)
        end
      end

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }

        it 'returns the end of the previous period' do
          expect(result).to eq((date_service.from_date - 1.day).to_s)
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_date) { DateTime.parse('02 Mar 2022') }

      it 'returns to_date' do
        expect(result).to eq(date_service.to_date.to_s)
      end

      context 'when subscription is terminated in the middle of a period' do
        let(:terminated_at) { DateTime.parse('06 Mar 2022') }

        before do
          subscription.update!(status: :terminated, terminated_at: terminated_at)
        end

        it 'returns the terminated date' do
          expect(result).to eq(subscription.terminated_at.to_date.to_s)
        end
      end

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }

        it 'returns the end of the previous period' do
          expect(result).to eq((date_service.from_date - 1.day).to_s)
        end
      end
    end
  end

  describe 'next_end_of_period' do
    let(:result) { date_service.next_end_of_period.to_s }

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

  describe 'previous_beginning_of_period' do
    let(:result) { date_service.previous_beginning_of_period(current_period: current_period).to_s }

    let(:current_period) { false }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns the first day of the previous month' do
        expect(result).to eq('2022-02-01')
      end

      context 'with current period argument' do
        let(:current_period) { true }

        it 'returns the first day of the month' do
          expect(result).to eq('2022-03-01')
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }

      it 'returns the beginning of the previous period' do
        expect(result).to eq('2022-02-02')
      end

      context 'with current period argument' do
        let(:current_period) { true }

        it 'returns the beginning of the current period' do
          expect(result).to eq('2022-03-02')
        end
      end
    end
  end

  describe 'single_day_price' do
    let(:result) { date_service.single_day_price }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns the price of single day' do
        expect(result).to eq(plan.amount_cents.fdiv(28))
      end

      context 'when on a leap year' do
        let(:subscription_date) { DateTime.parse('28 Feb 2019') }
        let(:billing_date) { DateTime.parse('01 Mar 2020') }

        it 'returns the price of single day' do
          expect(result).to eq(plan.amount_cents.fdiv(29))
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }

      it 'returns the price of single day' do
        expect(result).to eq(plan.amount_cents.fdiv(28))
      end

      context 'when on a leap year' do
        let(:subscription_date) { DateTime.parse('02 Feb 2019') }
        let(:billing_date) { DateTime.parse('08 Mar 2020') }

        it 'returns the price of single day' do
          expect(result).to eq(plan.amount_cents.fdiv(29))
        end
      end
    end
  end

  describe 'charges_duration_in_days' do
    let(:result) { date_service.charges_duration_in_days }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns the month duration' do
        expect(result).to eq(28)
      end

      context 'when on a leap year' do
        let(:subscription_date) { DateTime.parse('28 Feb 2019') }
        let(:billing_date) { DateTime.parse('01 Mar 2020') }

        it 'returns the month duration' do
          expect(result).to eq(29)
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }

      it 'returns the month duration' do
        expect(result).to eq(28)
      end

      context 'when on a leap year' do
        let(:subscription_date) { DateTime.parse('02 Feb 2019') }
        let(:billing_date) { DateTime.parse('08 Mar 2020') }

        it 'returns the month duration' do
          expect(result).to eq(29)
        end
      end
    end
  end
end
