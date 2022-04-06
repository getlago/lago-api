# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillingService, type: :service do
  subject(:billing_service) { described_class.new }

  describe '.call' do
    context 'when billed monthly on subscription date' do
      let(:plan) { create(:plan, interval: :monthly, billing_period: :subscription_date) }

      context 'when subscription date is any day below 28' do
        let(:start_date) { DateTime.parse('04 Jan 2022') }
        let(:subscription) { create(:subscription, plan: plan, started_at: start_date) }

        before { subscription }

        it 'enqueue a job on billing day' do
          current_date = DateTime.parse('04 Mar 2022')

          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with(subscription, current_date.to_i)
          end
        end

        it 'does not enqueue a job on other day' do
          current_date = DateTime.parse('07 Mar 2022')

          travel_to(current_date) do
            expect { billing_service.call }.not_to have_enqueued_job
          end
        end
      end

      context 'when last day of month and subscription date is after 28 while current month has only 28 days' do
        let(:start_date) { DateTime.parse('30 Jan 2022') }
        let(:subscription) { create(:subscription, plan: plan, started_at: start_date) }

        before { subscription }

        it 'enqueue a job on billing day' do
          current_date = DateTime.parse('28 Feb 2022')

          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with(subscription, current_date.to_i)
          end
        end

        it 'does not enqueue a job on other day' do
          current_date = DateTime.parse('31 Mar 2022')

          travel_to(current_date) do
            expect { billing_service.call }.not_to have_enqueued_job
          end
        end
      end
    end

    context 'when billed yearly on subscription date' do
      let(:plan) { create(:plan, interval: :yearly, billing_period: :subscription_date) }

      context 'when subscription date is any day' do
        let(:start_date) { DateTime.parse('04 Jan 2021') }
        let(:subscription) { create(:subscription, plan: plan, started_at: start_date) }

        before { subscription }

        it 'enqueue a job on billing day' do
          current_date = DateTime.parse('04 Jan 2022')

          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with(subscription, current_date.to_i)
          end
        end

        it 'does not enqueue a job on other day' do
          current_date = DateTime.parse('31 Mar 2022')

          travel_to(current_date) do
            expect { billing_service.call }.not_to have_enqueued_job
          end
        end
      end

      context 'when subscription date is on 29 feb and actual year is leap' do
        let(:start_date) { DateTime.parse('29 Feb 2016') }
        let(:subscription) { create(:subscription, plan: plan, started_at: start_date) }

        before { subscription }

        it 'enqueues a job on 29/02' do
          current_date = DateTime.parse('29 Feb 2020')

          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with(subscription, current_date.to_i)
          end
        end

        it 'does not enqueue a job on 28/02' do
          current_date = DateTime.parse('28 Feb 2020')

          travel_to(current_date) do
            expect { billing_service.call }.not_to have_enqueued_job
          end
        end

        it 'does not enqueue a job on any othe day' do
          current_date = DateTime.parse('31 Mar 2022')

          travel_to(current_date) do
            expect { billing_service.call }.not_to have_enqueued_job
          end
        end
      end

      context 'when subscription date is on 29 feb, actual year is not leap' do
        let(:start_date) { DateTime.parse('29 Feb 2016') }
        let(:subscription) { create(:subscription, plan: plan, started_at: start_date) }

        before { subscription }

        it 'enqueues a job on 28/02' do
          current_date = DateTime.parse('28 Feb 2022')

          travel_to(current_date) do
            billing_service.call

            expect(BillSubscriptionJob).to have_been_enqueued
              .with(subscription, current_date.to_i)
          end
        end

        it 'does not enqueue a job on any othe day' do
          current_date = DateTime.parse('31 Mar 2022')

          travel_to(current_date) do
            expect { billing_service.call }.not_to have_enqueued_job
          end
        end
      end
    end

    context 'when billed monthly on beginning of period' do
      let(:plan) { create(:plan, interval: :monthly, billing_period: :beginning_of_period) }

      let(:start_date) { DateTime.parse('20 Feb 2021') }
      let(:subscription) { create(:subscription, plan: plan, started_at: start_date) }

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

    context 'when billed yearly on beginning of period' do
      let(:plan) { create(:plan, interval: :yearly, billing_period: :beginning_of_period) }

      let(:start_date) { DateTime.parse('20 Feb 2021') }
      let(:subscription) { create(:subscription, plan: plan, started_at: start_date) }

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
        current_date = DateTime.parse('02 Janv 2022')

        travel_to(current_date) do
          expect { billing_service.call }.not_to have_enqueued_job
        end
      end
    end
  end
end
