# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillingService, type: :service do
  subject(:billing_service) { described_class.new }

  describe '.call' do
    let(:start_date) { DateTime.parse('20 Feb 2021') }

    context 'when billed weekly' do
      let(:plan) { create(:plan, interval: :weekly) }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: start_date,
          started_at: Time.zone.now,
        )
      end

      before { subscription }

      it 'enqueue a job on billing day' do
        current_date = DateTime.parse('20 Jun 2022')

        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with(subscription, current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        current_date = DateTime.parse('21 Jun 2022')

        travel_to(current_date) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end

    context 'when billed monthly' do
      let(:plan) { create(:plan, interval: :monthly) }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: start_date,
          started_at: Time.zone.now,
        )
      end

      before { subscription }

      it 'enqueue a job on billing day' do
        current_date = DateTime.parse('01 Feb 2022')

        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with(subscription, current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        current_date = DateTime.parse('02 Feb 2022')

        travel_to(current_date) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end

    context 'when billed yearly' do
      let(:plan) { create(:plan, interval: :yearly) }

      let(:subscription) do
        create(
          :subscription,
          plan: plan,
          subscription_date: start_date,
          started_at: Time.zone.now,
        )
      end

      before { subscription }

      it 'enqueue a job on billing day' do
        current_date = DateTime.parse('01 Jan 2022')

        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with(subscription, current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        current_date = DateTime.parse('02 Jan 2022')

        travel_to(current_date) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'when charges are billed monthly' do
        before { plan.update(bill_charges_monthly: true) }

        it 'enqueues a job on billing day' do
          current_date = DateTime.parse('01 Feb 2022')

          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with(subscription, current_date.to_i)
          end
        end
      end
    end

    context 'when downgraded' do
      let(:subscription) do
        create(
          :subscription,
          subscription_date: start_date,
          started_at: Time.zone.now,
          previous_subscription: previous_subscription,
          status: :pending,
        )
      end

      let(:previous_subscription) do
        create(
          :subscription,
          subscription_date: start_date,
          started_at: Time.zone.now,
        )
      end

      before { subscription }

      it 'enqueue a job on billing day' do
        current_date = DateTime.parse('01 Feb 2022')

        travel_to(current_date) do
          billing_service.call

          expect(Subscriptions::TerminateJob).to have_been_enqueued
            .with(previous_subscription, current_date.to_i)
        end
      end
    end
  end
end
