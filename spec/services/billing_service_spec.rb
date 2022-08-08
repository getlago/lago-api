# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillingService, type: :service do
  subject(:billing_service) { described_class.new }

  describe '.call' do
    let(:plan) { create(:plan, interval: interval, bill_charges_monthly: bill_charges_monthly) }
    let(:bill_charges_monthly) { false }
    let(:subscription_date) { DateTime.parse('20 Feb 2021') }
    let(:customer) { create(:customer) }

    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        subscription_date: subscription_date,
        started_at: Time.zone.now,
        billing_time: billing_time,
      )
    end

    before { subscription }

    context 'when billed weekly with calendar billing time' do
      let(:interval) { :weekly }
      let(:billing_time) { :calendar }

      let(:subscription1) do
        create(
          :subscription,
          customer: customer,
          plan: plan,
          subscription_date: subscription_date,
          started_at: Time.zone.now,
        )
      end

      let(:subscription2) do
        create(
          :subscription,
          customer: customer,
          plan: plan,
          subscription_date: subscription_date,
          started_at: Time.zone.now,
        )
      end

      let(:subscription3) do
        create(
          :subscription,
          plan: plan,
          subscription_date: subscription_date,
          started_at: Time.zone.now,
        )
      end

      before do
        subscription1
        subscription2
        subscription3
      end

      it 'enqueues a job on billing day' do
        current_date = DateTime.parse('20 Jun 2022')

        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with(match_array([subscription1, subscription2]), current_date.to_i)

          expect(BillSubscriptionJob).to have_been_enqueued
             .with([subscription3], current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        current_date = DateTime.parse('21 Jun 2022')

        travel_to(current_date) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end

    context 'when billed monthly with calendar billing time' do
      let(:interval) { :monthly }
      let(:billing_time) { :calendar }

      it 'enqueues a job on billing day' do
        current_date = DateTime.parse('01 Feb 2022')

        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        current_date = DateTime.parse('02 Feb 2022')

        travel_to(current_date) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end

    context 'when billed yearly with calendar billing time' do
      let(:interval) { :yearly }
      let(:billing_time) { :calendar }

      it 'enqueues a job on billing day' do
        current_date = DateTime.parse('01 Jan 2022')

        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        current_date = DateTime.parse('02 Jan 2022')

        travel_to(current_date) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'when charges are billed monthly' do
        let(:bill_charges_monthly) { true }

        it 'enqueues a job on billing day' do
          current_date = DateTime.parse('01 Feb 2022')

          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i)
          end
        end
      end
    end

    context 'when billed weekly with anniversary billing time' do
      let(:interval) { :weekly }
      let(:billing_time) { :anniversary }

      let(:subscription_date) { DateTime.now.prev_occurring(DateTime.now.strftime('%A').downcase.to_sym) }

      let(:current_date) { DateTime.parse('20 Jun 2022').prev_occurring(subscription_date.strftime('%A').downcase.to_sym) }

      it 'enqueues a job on billing day' do
        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end

    context 'when billed monthly with anniversary billing time' do
      let(:interval) { :monthly }
      let(:billing_time) { :anniversary }
      let(:current_date) { subscription_date.next_month }

      it 'enqueues a job on billing day' do
        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'when subscription anniversary is on a 31st' do
        let(:subscription_date) { DateTime.parse('31 Mar 2021') }
        let(:current_date) { DateTime.parse('28 Feb 2022') }

        it 'enqueues a job if the month count less than 31 days' do
          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i)
          end
        end
      end
    end

    context 'when billed yearly with anniversary billing time' do
      let(:interval) { :yearly }
      let(:billing_time) { :anniversary }

      let(:current_date) { subscription_date.next_year }

      it 'enqueues a job on billing day' do
        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i)
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'when subscription anniversary is on 29th of february' do
        let(:subscription_date) { DateTime.parse('29 Feb 2020') }
        let(:current_date) { DateTime.parse('28 Feb 2022') }

        it 'enqueues a job on 28th of february when year is not a leap year' do
          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i)
          end
        end
      end

      context 'when charges are billed monthly' do
        let(:bill_charges_monthly) { true }
        let(:current_date) { subscription_date.next_month }

        it 'enqueues a job on billing day' do
          travel_to(current_date.next_month) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.next_month.to_i)
          end
        end

        context 'when subscription anniversary is on a 31st' do
          let(:subscription_date) { DateTime.parse('31 Mar 2021') }
          let(:current_date) { DateTime.parse('28 Feb 2022') }

          it 'enqueues a job if the month count less than 31 days' do
            travel_to(current_date) do
              billing_service.call

              expect(BillSubscriptionJob).to have_been_enqueued
                .with([subscription], current_date.to_i)
            end
          end
        end
      end
    end

    context 'when downgraded' do
      let(:subscription) do
        create(
          :subscription,
          subscription_date: subscription_date,
          started_at: Time.zone.now,
          previous_subscription: previous_subscription,
          status: :pending,
        )
      end

      let(:previous_subscription) do
        create(
          :subscription,
          subscription_date: subscription_date,
          started_at: Time.zone.now,
        )
      end

      before { subscription }

      it 'enqueues a job on billing day' do
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
