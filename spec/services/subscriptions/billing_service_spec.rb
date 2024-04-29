# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::BillingService, type: :service do
  subject(:billing_service) { described_class.new }

  describe '.call' do
    let(:plan) { create(:plan, interval:, bill_charges_monthly:) }
    let(:bill_charges_monthly) { false }
    let(:subscription_at) { DateTime.parse('20 Feb 2021') }
    let(:customer) { create(:customer) }

    let(:subscription) do
      create(
        :subscription,
        plan:,
        subscription_at:,
        started_at: Time.zone.now,
        billing_time:,
      )
    end

    before { subscription }

    context 'when billed weekly with calendar billing time' do
      let(:interval) { :weekly }
      let(:billing_time) { :calendar }

      let(:subscription1) do
        create(
          :subscription,
          customer:,
          plan:,
          subscription_at:,
          started_at: Time.zone.now,
        )
      end

      let(:subscription2) do
        create(
          :subscription,
          customer:,
          plan:,
          subscription_at:,
          started_at: Time.zone.now,
        )
      end

      let(:subscription3) do
        create(
          :subscription,
          plan:,
          subscription_at:,
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
            .with(
              contain_exactly(subscription1, subscription2),
              current_date.to_i,
              invoicing_reason: :subscription_periodic,
            )

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription3], current_date.to_i, invoicing_reason: :subscription_periodic)
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
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        end
      end

      it 'does not enqueue a job on other day' do
        current_date = DateTime.parse('02 Feb 2022')

        travel_to(current_date) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'when ending_at is the same as billing day' do
        let(:billing_date) { DateTime.parse('01 Feb 2022') }
        let(:subscription) do
          create(
            :subscription,
            plan:,
            subscription_at:,
            started_at: Time.zone.now,
            billing_time:,
            ending_at: billing_date,
          )
        end

        it 'does not enqueue a job on billing day' do
          travel_to(billing_date) do
            billing_service.call

            expect(BillSubscriptionJob).not_to have_been_enqueued
              .with([subscription], billing_date.to_i, invoicing_reason: :subscription_periodic)
          end
        end
      end
    end

    context 'when billed quarterly with calendar billing time' do
      let(:interval) { :quarterly }
      let(:billing_time) { :calendar }

      it 'enqueues a job on billing day' do
        current_date = DateTime.parse('01 Apr 2022')

        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        end
      end

      it 'does not enqueue a job on other day' do
        current_date = DateTime.parse('01 May 2022')

        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).not_to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
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
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
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
              .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          end
        end
      end
    end

    context 'when billed weekly with anniversary billing time' do
      let(:interval) { :weekly }
      let(:billing_time) { :anniversary }

      let(:current_date) do
        DateTime.parse('20 Jun 2022').prev_occurring(subscription_at.strftime('%A').downcase.to_sym)
      end

      it 'enqueues a job on billing day' do
        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
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
      let(:current_date) { subscription_at.next_month }

      it 'enqueues a job on billing day' do
        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'when subscription anniversary is on a 31st' do
        let(:subscription_at) { DateTime.parse('31 Mar 2021') }
        let(:current_date) { DateTime.parse('28 Feb 2022') }

        it 'enqueues a job if the month count less than 31 days' do
          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          end
        end
      end
    end

    context 'when billed quarterly with anniversary billing time' do
      let(:interval) { :quarterly }
      let(:billing_time) { :anniversary }
      let(:current_date) { subscription_at + 3.months }

      it 'enqueues a job on billing day' do
        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'when subscription anniversary is in March' do
        let(:subscription_at) { DateTime.parse('15 Mar 2021') }
        let(:current_date) { DateTime.parse('15 Sep 2022') }

        it 'enqueues a job' do
          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          end
        end
      end

      context 'when subscription anniversary is on a 31st' do
        let(:subscription_at) { DateTime.parse('31 Mar 2021') }
        let(:current_date) { DateTime.parse('30 Jun 2022') }

        it 'enqueues a job if the month count less than 31 days' do
          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          end
        end
      end
    end

    context 'when billed yearly with anniversary billing time' do
      let(:interval) { :yearly }
      let(:billing_time) { :anniversary }

      let(:current_date) { subscription_at.next_year }

      it 'enqueues a job on billing day' do
        travel_to(current_date) do
          billing_service.call

          expect(BillSubscriptionJob).to have_been_enqueued
            .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
        end
      end

      it 'does not enqueue a job on other day' do
        travel_to(current_date + 1.day) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'when subscription anniversary is on 29th of february' do
        let(:subscription_at) { DateTime.parse('29 Feb 2020') }
        let(:current_date) { DateTime.parse('28 Feb 2022') }

        it 'enqueues a job on 28th of february when year is not a leap year' do
          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
          end
        end
      end

      context 'when charges are billed monthly' do
        let(:bill_charges_monthly) { true }
        let(:current_date) { subscription_at.next_month }

        it 'enqueues a job on billing day' do
          travel_to(current_date.next_month) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with([subscription], current_date.next_month.to_i, invoicing_reason: :subscription_periodic)
          end
        end

        context 'when subscription anniversary is on a 31st' do
          let(:subscription_at) { DateTime.parse('31 Mar 2021') }
          let(:current_date) { DateTime.parse('28 Feb 2022') }

          it 'enqueues a job if the month count less than 31 days' do
            travel_to(current_date) do
              billing_service.call

              expect(BillSubscriptionJob).to have_been_enqueued
                .with([subscription], current_date.to_i, invoicing_reason: :subscription_periodic)
            end
          end
        end
      end
    end

    context 'when downgraded' do
      let(:subscription) do
        create(
          :subscription,
          subscription_at:,
          started_at: Time.zone.now,
          previous_subscription:,
          status: :pending,
        )
      end

      let(:previous_subscription) do
        create(
          :subscription,
          subscription_at:,
          started_at: Time.zone.now,
          billing_time: :anniversary,
        )
      end

      before { subscription }

      it 'enqueues a job on billing day' do
        current_date = DateTime.parse('20 Feb 2022')

        travel_to(current_date) do
          billing_service.call

          expect(Subscriptions::TerminateJob).to have_been_enqueued
            .with(previous_subscription, current_date.to_i)
        end
      end
    end

    context 'when on subscription creation day' do
      let(:subscription) do
        create(
          :subscription,
          customer:,
          plan:,
          subscription_at:,
          started_at:,
          billing_time:,
          created_at: subscription_at,
        )
      end

      let(:interval) { :monthly }
      let(:billing_time) { :anniversary }
      let(:subscription_at) { DateTime.parse('2022-12-13T12:00:00Z') }
      let(:started_at) { subscription_at }
      let(:customer) { create(:customer, organization: plan.organization, timezone:) }
      let(:timezone) { nil }

      it 'does not enqueue a job' do
        travel_to(subscription_at) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'with customer timezone' do
        let(:timezone) { 'Pacific/Noumea' }

        it 'does not enqueue a job' do
          travel_to(subscription_at + 10.hours) do
            expect { billing_service.call }.not_to have_enqueued_job
          end
        end
      end
    end

    context 'when subscription was already automatically billed today' do
      let(:interval) { :monthly }
      let(:billing_time) { :anniversary }
      let(:subscription_at) { DateTime.parse('20 Feb 2021T12:00:00') }

      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          subscription:,
          invoicing_reason: :subscription_periodic,
          timestamp: subscription_at - 1.hour,
          recurring: true,
        )
      end

      before { invoice_subscription }

      it 'does not enqueue a job' do
        travel_to(subscription_at) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end

      context 'with customer timezone' do
        let(:timezone) { 'Pacific/Noumea' }

        it 'does not enqueue a job' do
          travel_to(subscription_at + 10.hours) do
            expect { billing_service.call }.not_to have_enqueued_job
          end
        end
      end
    end
  end
end
