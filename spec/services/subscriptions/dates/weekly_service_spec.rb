# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::Dates::WeeklyService, type: :service do
  subject(:date_service) { described_class.new(subscription, billing_at, false) }

  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      subscription_at:,
      billing_time:,
      started_at:,
    )
  end

  let(:customer) { create(:customer, timezone:) }
  let(:plan) { create(:plan, interval: :weekly, pay_in_advance:) }
  let(:pay_in_advance) { false }

  let(:subscription_at) { DateTime.parse('02 Feb 2021') }
  let(:billing_at) { DateTime.parse('07 Mar 2022') }
  let(:started_at) { subscription_at }
  let(:timezone) { 'UTC' }

  describe 'from_datetime' do
    let(:result) { date_service.from_datetime.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns the beginning of the previous week' do
        expect(result).to eq('2022-02-28 00:00:00 UTC')
        expect(Time.zone.parse(result).wday).to eq(1)
      end

      context 'with customer timezone' do
        let(:timezone) { 'America/New_York' }

        it 'takes customer timezone into account' do
          expect(result).to eq('2022-02-21 05:00:00 UTC')
        end
      end

      context 'when date is before the start date' do
        let(:started_at) { DateTime.parse('01 Mar 2022 05:00:00') }

        it 'returns the start date' do
          expect(result).to eq(started_at.beginning_of_day.utc.to_s)
        end

        context 'with customer timezone' do
          let(:timezone) { 'America/New_York' }

          it 'returns the start date' do
            expect(result).to eq(started_at.utc.to_s)
          end
        end
      end

      context 'when subscription is just terminated' do
        let(:billing_at) { DateTime.parse('10 Mar 2022') }

        before { subscription.terminated! }

        it 'returns the beginning of the week' do
          expect(result).to eq('2022-03-07 00:00:00 UTC')
          expect(Time.zone.parse(result).wday).to eq(1)
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'returns the beginning of the current week' do
            expect(result).to eq('2022-03-07 00:00:00 UTC')
            expect(Time.zone.parse(result).wday).to eq(1)
          end
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_at) { DateTime.parse('09 Mar 2022') }

      it 'returns the previous week week day' do
        expect(result).to eq('2022-03-01 00:00:00 UTC')
        expect(Time.zone.parse(result).wday).to eq(subscription_at.wday)
      end

      context 'when date is before the start date' do
        let(:started_at) { DateTime.parse('08 Mar 2022') }

        it 'returns the start date' do
          expect(result).to eq(started_at.utc.to_s)
          expect(Time.zone.parse(result).wday).to eq(subscription_at.wday)
        end
      end

      context 'when subscription is just terminated' do
        before { subscription.terminated! }

        it 'returns the previous week day' do
          expect(result).to eq('2022-03-08 00:00:00 UTC')
          expect(Time.zone.parse(result).wday).to eq(subscription_at.wday)
        end

        context 'when plan is pay in advance' do
          let(:pay_in_advance) { true }

          it 'returns the current week week day' do
            expect(result).to eq('2022-03-08 00:00:00 UTC')
            expect(Time.zone.parse(result).wday).to eq(subscription_at.wday)
          end
        end
      end
    end
  end

  describe 'to_datetime' do
    let(:result) { date_service.to_datetime.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }
      let(:billing_at) { DateTime.parse('07 Mar 2022') }

      it 'returns the end of the previous week' do
        expect(result).to eq('2022-03-06 23:59:59 UTC')
      end

      context 'with customer timezone' do
        let(:timezone) { 'America/New_York' }

        it 'takes customer timezone into account' do
          expect(result).to eq('2022-02-28 04:59:59 UTC')
        end
      end

      context 'when plan is pay in advance' do
        before { plan.update!(pay_in_advance: true) }

        it 'returns the end of the week' do
          expect(result).to eq('2022-03-13 23:59:59 UTC')
          expect(Time.zone.parse(result).wday).to eq(0)
        end
      end

      context 'when subscription is just terminated' do
        let(:billing_at) { DateTime.parse('07 Mar 2022') }
        let(:terminated_at) { DateTime.parse('02 Mar 2022') }

        before do
          subscription.update!(
            status: :terminated,
            terminated_at:,
          )
        end

        it 'returns the termination date' do
          expect(result).to eq(subscription.terminated_at.utc.to_s)
        end

        context 'with customer timezone' do
          let(:timezone) { 'America/New_York' }

          it 'returns the termination date' do
            expect(result).to eq(subscription.terminated_at.utc.to_s)
          end
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_at) { DateTime.parse('09 Mar 2022') }

      it 'returns the previous week week day' do
        expect(result).to eq('2022-03-07 23:59:59 UTC')
      end

      context 'when plan is pay in advance' do
        before { plan.update!(pay_in_advance: true) }

        it 'returns the end of the current period' do
          expect(result).to eq('2022-03-14 23:59:59 UTC')
        end
      end

      context 'when subscription is just terminated' do
        before do
          subscription.update!(
            status: :terminated,
            terminated_at: DateTime.parse('02 Mar 2022'),
          )
        end

        it 'returns the termination date' do
          expect(result).to eq(subscription.terminated_at.utc.to_s)
        end
      end
    end
  end

  describe 'charges_from_datetime' do
    let(:result) { date_service.charges_from_datetime.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns from_date' do
        expect(result).to eq(date_service.from_datetime.to_s)
      end

      context 'with customer timezone' do
        let(:timezone) { 'America/New_York' }

        it 'takes customer timezone into account' do
          expect(result).to eq(date_service.from_datetime.to_s)
        end

        context 'when timezone has changed' do
          let(:billing_at) { DateTime.parse('08 Mar 2022') }

          let(:previous_invoice_subscription) do
            create(
              :invoice_subscription,
              subscription:,
              charges_to_datetime: '2022-02-27T22:59:59Z',
            )
          end

          before do
            previous_invoice_subscription
            subscription.customer.update!(timezone: 'America/Los_Angeles')
          end

          it 'takes previous invoice into account' do
            expect(result).to match_datetime('2022-02-27 23:00:00')
          end
        end
      end

      context 'when subscription started in the middle of a period' do
        let(:started_at) { DateTime.parse('03 Mar 2022') }

        it 'returns the start date' do
          expect(result).to eq(subscription.started_at.utc.to_s)
        end
      end

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }

        it 'returns the start of the previous period' do
          expect(result).to eq((date_service.from_datetime - 1.week).to_s)
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_at) { DateTime.parse('09 Mar 2022') }

      it 'returns from_date' do
        expect(result).to eq(date_service.from_datetime.to_s)
      end

      context 'when subscription started in the middle of a period' do
        let(:started_at) { DateTime.parse('03 Mar 2022') }

        it 'returns the start date' do
          expect(result).to eq(subscription.started_at.utc.to_s)
        end
      end

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }

        it 'returns the start of the previous period' do
          expect(result).to eq((date_service.from_datetime - 1.week).to_s)
        end
      end
    end
  end

  describe 'charges_to_datetime' do
    let(:result) { date_service.charges_to_datetime.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns to_date' do
        expect(result).to eq(date_service.to_datetime.to_s)
      end

      context 'with customer timezone' do
        let(:timezone) { 'America/New_York' }

        it 'takes customer timezone into account' do
          expect(result).to eq(date_service.to_datetime.to_s)
        end
      end

      context 'when subscription is terminated in the middle of a period' do
        let(:terminated_at) { DateTime.parse('06 Mar 2022') }

        before do
          subscription.update!(status: :terminated, terminated_at:)
        end

        it 'returns the terminated date' do
          expect(result).to eq(subscription.terminated_at.utc.to_s)
        end
      end

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }

        it 'returns the end of the previous period' do
          expect(result).to eq((date_service.from_datetime - 1.day).end_of_day.to_s)
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_at) { DateTime.parse('09 Mar 2022') }

      it 'returns to_date' do
        expect(result).to eq(date_service.to_datetime.to_s)
      end

      context 'when subscription is terminated in the middle of a period' do
        let(:terminated_at) { DateTime.parse('06 Mar 2022') }

        before do
          subscription.update!(status: :terminated, terminated_at:)
        end

        it 'returns the terminated date' do
          expect(result).to eq(subscription.terminated_at.utc.to_s)
        end
      end

      context 'when plan is pay in advance' do
        let(:pay_in_advance) { true }

        it 'returns the end of the previous period' do
          expect(result).to eq((date_service.from_datetime - 1.day).end_of_day.to_s)
        end
      end
    end
  end

  describe 'next_end_of_period' do
    let(:result) { date_service.next_end_of_period.to_s }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns the last day of the week' do
        expect(result).to eq('2022-03-13 23:59:59 UTC')
      end

      context 'with customer timezone' do
        let(:timezone) { 'America/New_York' }

        it 'takes customer timezone into account' do
          expect(result).to eq('2022-03-07 04:59:59 UTC')
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }
      let(:billing_at) { DateTime.parse('08 Mar 2022 20:00:00') }

      it 'returns the end of the billing week' do
        expect(result).to eq('2022-03-14 23:59:59 UTC')
      end

      context 'with customer timezone' do
        let(:timezone) { 'America/New_York' }

        it 'takes customer timezone into account' do
          expect(result).to eq('2022-03-14 03:59:59 UTC')
        end
      end

      context 'when date is the end of the period' do
        let(:billing_at) { DateTime.parse('07 Mar 2022') }

        it 'returns the date' do
          expect(result).to eq(billing_at.utc.end_of_day.to_s)
        end
      end
    end
  end

  describe 'compute_previous_beginning_of_period' do
    let(:result) { date_service.previous_beginning_of_period(current_period:).to_s }

    let(:current_period) { false }

    context 'when billing_time is calendar' do
      let(:billing_time) { :calendar }

      it 'returns the first day of the previous week' do
        expect(result).to eq('2022-02-28 00:00:00 UTC')
      end

      context 'with customer timezone' do
        let(:timezone) { 'America/New_York' }

        it 'takes customer timezone into account' do
          expect(result).to eq('2022-02-21 05:00:00 UTC')
        end
      end

      context 'with current period argument' do
        let(:current_period) { true }

        it 'returns the first day of the week' do
          expect(result).to eq('2022-03-07 00:00:00 UTC')
        end
      end
    end

    context 'when billing_time is anniversary' do
      let(:billing_time) { :anniversary }

      it 'returns the beginning of the previous period' do
        expect(result).to eq('2022-02-22 00:00:00 UTC')
      end

      context 'with customer timezone' do
        let(:timezone) { 'America/New_York' }

        it 'takes customer timezone into account' do
          expect(result).to eq('2022-02-21 05:00:00 UTC')
        end
      end

      context 'with current period argument' do
        let(:current_period) { true }

        it 'returns the beginning of the current period' do
          expect(result).to eq('2022-03-01 00:00:00 UTC')
        end
      end
    end
  end

  describe 'single_day_price' do
    let(:billing_time) { :anniversary }
    let(:billing_at) { DateTime.parse('08 Mar 2022') }
    let(:result) { date_service.single_day_price }

    it 'returns the price of single day' do
      expect(result).to eq(plan.amount_cents.fdiv(7))
    end
  end

  describe 'charges_duration_in_days' do
    let(:billing_time) { :anniversary }
    let(:billing_at) { DateTime.parse('08 Mar 2022') }
    let(:result) { date_service.charges_duration_in_days }

    it 'returns the duration of the period' do
      expect(result).to eq(7)
    end
  end
end
