# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubscriptionsService, type: :service do
  subject(:subscription_service) { described_class.new }

  let(:organization) { create(:organization) }

  describe '.create' do
    let(:plan) { create(:plan, amount_cents: 100, organization: organization) }
    let(:customer) { create(:customer, organization: organization) }

    let(:params) do
      {
        customer_id: customer.customer_id,
        plan_code: plan.code,
      }
    end

    it 'creates a subscription' do
      result = subscription_service.create(
        organization: organization,
        params: params,
      )

      expect(result).to be_success

      subscription = result.subscription

      aggregate_failures do
        expect(subscription.customer_id).to eq(customer.id)
        expect(subscription.plan_id).to eq(plan.id)
        expect(subscription.started_at).to be_present
        expect(subscription.anniversary_date).to be_present
        expect(subscription).to be_active
      end
    end

    context 'when customer does not exists' do
      let(:params) do
        {
          customer_id: SecureRandom.uuid,
          plan_code: plan.code,
        }
      end

      it 'creates a customer' do
        result = subscription_service.create(
          organization: organization,
          params: params,
        )

        expect(result).to be_success

        subscription = result.subscription

        aggregate_failures do
          expect(subscription.customer.customer_id).to eq(params[:customer_id])
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at).to be_present
          expect(subscription.anniversary_date).to be_present
          expect(subscription).to be_active
        end
      end

      context 'when plan is pay_in_advance' do
        before { plan.update(pay_in_advance: true) }

        it 'enqueued a job to bill the subscription' do
          expect do
            subscription_service.create(
              organization: organization,
              params: params,
            )
          end.to have_enqueued_job(BillSubscriptionJob)
        end
      end
    end

    context 'when customer id is missing' do
      let(:params) do
        {
          customer_id: nil,
          plan_code: plan.code,
        }
      end

      it 'fails' do
        result = subscription_service.create(
          organization: organization,
          params: params,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('unable to find customer')
      end
    end

    context 'when plan doest not exists' do
      let(:params) do
        {
          customer_id: customer.customer_id,
          plan_code: 'invalid_plan',
        }
      end

      it 'fails' do
        result = subscription_service.create(
          organization: organization,
          params: params,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('plan does not exists')
      end
    end

    context 'when an active subscription already exists' do
      let!(:subscription) do
        create(
          :subscription,
          customer: customer,
          plan: plan,
          status: :active,
          anniversary_date: Time.zone.now.to_date,
          started_at: Time.zone.now,
        )
      end

      context 'when plan is the same' do
        it 'returns existing subscription' do
          result = subscription_service.create(
            organization: organization,
            params: params,
          )

          expect(result).to be_success
          expect(result.subscription.id).to eq(subscription.id)
        end
      end

      context 'when plan is not the same' do
        context 'when we upgrade the plan' do
          let(:higher_plan) { create(:plan, amount_cents: 200, organization: organization) }
          let(:params) do
            {
              customer_id: customer.customer_id,
              plan_code: higher_plan.code,
            }
          end

          it 'terminates the existing subscription' do
            subscription_service.create(
              organization: organization,
              params: params,
            )

            old_subscription = Subscription.find(subscription.id)

            expect(old_subscription).to be_terminated
          end

          it 'creates a new subscription' do
            result = subscription_service.create(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result).to be_success
              expect(result.subscription.id).not_to eq(subscription.id)
              expect(result.subscription).to be_active
              expect(result.subscription.plan.id).to eq(higher_plan.id)
              expect(result.subscription.previous_subscription_id).to eq(subscription.id)
              expect(result.subscription.anniversary_date).to eq(subscription.anniversary_date)
            end
          end

          context 'when old subscription is payed in arrear' do
            before { plan.update!(pay_in_advance: false) }

            it 'enqueues a job to bill the existing subscription' do
              expect do
                subscription_service.create(
                  organization: organization,
                  params: params,
                )
              end.to have_enqueued_job(BillSubscriptionJob)
            end
          end

          context 'when new subscription is payed in advance' do
            before { higher_plan.update!(pay_in_advance: false) }

            it 'enqueues a job to bill the existing subscription' do
              expect do
                subscription_service.create(
                  organization: organization,
                  params: params,
                )
              end.to have_enqueued_job(BillSubscriptionJob)
            end
          end
        end

        context 'when we downgrade the plan' do
          let(:lower_plan) do
            create(:plan, amount_cents: 50, organization: organization)
          end

          let(:params) do
            {
              customer_id: customer.customer_id,
              plan_code: lower_plan.code,
            }
          end

          it 'creates a new subscription' do
            result = subscription_service.create(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result).to be_success

              next_subscription = result.subscription.next_subscription
              expect(next_subscription.id).not_to eq(subscription.id)
              expect(next_subscription).to be_pending
              expect(next_subscription.plan_id).to eq(lower_plan.id)
              expect(next_subscription.anniversary_date).to eq(subscription.anniversary_date)
              expect(next_subscription.previous_subscription).to eq(subscription)
            end
          end

          it 'keeps the current subscription' do
            result = subscription_service.create(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result.subscription.id).to eq(subscription.id)
              expect(result.subscription).to be_active
              expect(result.subscription.next_subscription).to be_present
            end
          end
        end
      end
    end
  end

  describe '.terminate_and_start_next' do
    let(:subscription) { create(:subscription) }
    let(:next_subscription) { create(:subscription, previous_subscription_id: subscription.id, status: :pending) }
    let(:timestamp) { Time.zone.now.to_i }

    before { next_subscription }

    it 'terminates the subscription' do
      result = subscription_service.terminate_and_start_next(
        subscription: subscription,
        timestamp: timestamp,
      )

      aggregate_failures do
        expect(result).to be_success
        expect(subscription.reload).to be_terminated
      end
    end

    it 'starts the next subscription' do
      result = subscription_service.terminate_and_start_next(
        subscription: subscription,
        timestamp: timestamp,
      )

      aggregate_failures do
        expect(result).to be_success
        expect(result.subscription.id).to eq(next_subscription.id)
        expect(result.subscription).to be_active
      end
    end

    context 'when terminated subscription is payed in arrear' do
      before { subscription.plan.update!(pay_in_advance: false) }

      it 'enqueues a job to bill the existing subscription' do
        expect do
          subscription_service.terminate_and_start_next(
            subscription: subscription,
            timestamp: timestamp,
          )
        end.to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context 'when next subscription is payed in advance' do
      let(:plan) { create(:plan, pay_in_advance: true) }
      let(:next_subscription) do
        create(
          :subscription,
          previous_subscription_id: subscription.id,
          plan: plan,
          status: :pending,
        )
      end

      before { subscription.plan.update!(pay_in_advance: true) }

      it 'enqueues a job to bill the existing subscription' do
        expect do
          subscription_service.terminate_and_start_next(
            subscription: subscription,
            timestamp: timestamp,
          )
        end.to have_enqueued_job(BillSubscriptionJob)
      end
    end
  end
end
