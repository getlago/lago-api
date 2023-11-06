# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::CreateService, type: :service do
  subject(:create_service) { described_class.new(customer:, plan:, params:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, amount_cents: 100, organization:, amount_currency: 'EUR') }
  let(:customer) { create(:customer, organization:, currency: 'EUR') }

  let(:external_id) { SecureRandom.uuid }
  let(:billing_time) { 'anniversary' }
  let(:subscription_at) { nil }
  let(:external_customer_id) { customer.external_id }
  let(:plan_code) { plan.code }
  let(:subscription_id) { nil }
  let(:name) { 'invoice display name' }

  let(:params) do
    {
      external_customer_id:,
      plan_code:,
      name:,
      external_id:,
      billing_time:,
      subscription_at:,
      subscription_id:,
    }
  end

  describe '#call' do
    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a subscription with subscription date set to current date' do
      result = create_service.call

      aggregate_failures do
        expect(result).to be_success

        subscription = result.subscription
        expect(subscription.customer_id).to eq(customer.id)
        expect(subscription.plan_id).to eq(plan.id)
        expect(subscription.started_at).to be_present
        expect(subscription.subscription_at).to be_present
        expect(subscription.name).to eq('invoice display name')
        expect(subscription).to be_active
        expect(subscription.external_id).to eq(external_id)
        expect(subscription).to be_anniversary
      end
    end

    it 'calls SegmentTrackJob' do
      subscription = create_service.call.subscription

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'subscription_created',
        properties: {
          created_at: subscription.created_at,
          customer_id: subscription.customer_id,
          plan_code: subscription.plan.code,
          plan_name: subscription.plan.name,
          subscription_type: 'create',
          organization_id: subscription.organization.id,
          billing_time: 'anniversary',
        },
      )
    end

    context 'when ending_at is passed' do
      let(:params) do
        {
          external_customer_id:,
          plan_code:,
          name:,
          external_id:,
          billing_time:,
          subscription_at:,
          subscription_id:,
          ending_at: Time.current.beginning_of_day + 3.months,
        }
      end

      it 'creates a subscription with ending_at correctly set' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          subscription = result.subscription
          expect(subscription.ending_at).to eq(Time.current.beginning_of_day + 3.months)
        end
      end
    end

    context 'when external_id is not given in an api context' do
      let(:external_id) { nil }

      before { CurrentContext.source = 'api' }

      it 'returns an error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:external_id]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'when billing_time is not provided' do
      let(:billing_time) { nil }

      it 'creates a calendar subscription' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.subscription).to be_calendar
        end
      end
    end

    context 'when License is free and plan_overrides is passed' do
      let(:params) do
        {
          external_customer_id:,
          plan_code:,
          name:,
          external_id:,
          billing_time:,
          subscription_at:,
          subscription_id:,
          plan_overrides: {
            amount_cents: 0,
          },
        }
      end

      it 'returns an error' do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq('feature_unavailable')
      end
    end

    context 'when customer does not exists in API context' do
      let(:customer) { Customer.new(organization:, external_id: SecureRandom.uuid) }

      before { CurrentContext.source = 'api' }

      it 'creates the customer' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          subscription = result.subscription
          expect(subscription.customer.external_id).to eq(customer.external_id)
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at).to be_present
          expect(subscription.subscription_at).to be_present
          expect(subscription).to be_active
        end
      end

      context 'when in graphql context' do
        let(:customer) { nil }
        let(:external_customer_id) { nil }

        before { CurrentContext.source = 'graphql' }

        it 'returns a customer_not_found error' do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.message).to eq('customer_not_found')
          end
        end
      end
    end

    context 'when plan is pay_in_advance but subscription is not active' do
      let(:plan) { create(:plan, amount_cents: 100, organization:, pay_in_advance: true) }
      let(:subscription_at) { Time.current + 1.hour }

      it 'does not enqueue a job to bill the subscription' do
        expect { create_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context 'when plan is pay_in_advance and subscription_at is current date' do
      let(:plan) { create(:plan, amount_cents: 100, organization:, pay_in_advance: true) }

      it 'enqueues a job to bill the subscription' do
        expect { create_service.call }.to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context 'when plan is pay_in_advance and subscription_at is in the future' do
      let(:plan) { create(:plan, amount_cents: 100, organization:, pay_in_advance: true) }
      let(:subscription_at) { Time.current + 5.days }

      it 'does not enqueue a job to bill the subscription' do
        expect { create_service.call }.not_to have_enqueued_job(BillSubscriptionJob)
      end
    end

    context 'when customer is missing' do
      let(:customer) { nil }
      let(:external_customer_id) { nil }

      it 'returns a customer_not_found error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('customer_not_found')
        end
      end
    end

    context 'when plan doest not exists' do
      let(:plan) { nil }
      let(:plan_code) { nil }

      it 'returns a plan_not_found error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('plan_not_found')
        end
      end
    end

    context 'when subscription_at is given and is invalid' do
      let(:subscription_at) { '2022-99-99T00:00:00Z' }

      it 'returns invalid_at error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:subscription_at]).to eq(['invalid_date'])
        end
      end
    end

    context 'when subscription_at is given and is in the future' do
      let(:subscription_at) { Time.current + 5.days }

      it 'creates a pending subscription' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          subscription = result.subscription
          expect(subscription.customer_id).to eq(customer.id)
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at).not_to be_present
          expect(subscription.subscription_at.to_s).to eq(subscription_at.to_s)
          expect(subscription.name).to eq('invoice display name')
          expect(subscription).to be_pending
          expect(subscription.external_id).to eq(external_id)
          expect(subscription).to be_anniversary
        end
      end
    end

    context 'when subscription_at is given and is in the past' do
      let(:subscription_at) { Time.current - 5.days }

      it 'creates a active subscription' do
        result = create_service.call

        aggregate_failures do
          expect(result).to be_success

          subscription = result.subscription
          expect(subscription.customer_id).to eq(customer.id)
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at.to_s).to eq(subscription_at.to_s)
          expect(subscription.subscription_at.to_s).to eq(subscription_at.to_s)
          expect(subscription.name).to eq('invoice display name')
          expect(subscription).to be_active
          expect(subscription.external_id).to eq(external_id)
          expect(subscription).to be_anniversary
        end
      end
    end

    context 'when billing_time is invalid' do
      let(:billing_time) { :foo }

      it 'fails' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to eq([:billing_time])
        end
      end
    end

    context 'when an active subscription already exists' do
      let(:subscription) do
        create(
          :subscription,
          customer:,
          plan: old_plan,
          status: :active,
          subscription_at: Time.current,
          started_at: Time.current,
          external_id:,
        )
      end

      let(:old_plan) { plan }

      before do
        CurrentContext.source = 'api'
        subscription
      end

      context 'when external_id is given' do
        it 'returns existing subscription' do
          result = create_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.subscription.id).to eq(subscription.id)
          end
        end
      end

      context 'when subscription_id is given' do
        let(:subscription_id) { subscription.id }

        before { CurrentContext.source = 'graphql' }

        it 'returns existing subscription' do
          result = create_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.subscription.id).to eq(subscription.id)
          end
        end
      end

      context 'when new plan has different currency than the old plan' do
        let(:plan) { create(:plan, amount_cents: 200, organization:, amount_currency: 'USD') }

        it 'fails' do
          result = create_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:currency)
            expect(result.error.messages[:currency]).to include('currencies_does_not_match')
          end
        end
      end

      context 'when plan is not the same' do
        context 'when we upgrade the plan' do
          let(:plan) { create(:plan, amount_cents: 200, organization:) }
          let(:old_plan) { create(:plan, amount_cents: 100, organization:) }
          let(:name) { 'invoice display name new' }

          it 'terminates the existing subscription' do
            expect { create_service.call }.to change { subscription.reload.status }.from('active').to('terminated')
          end

          it 'sends terminated and started subscription webhooks', :aggregate_failures do
            result = create_service.call
            expect(SendWebhookJob).to have_been_enqueued.with('subscription.terminated', subscription)
            expect(SendWebhookJob).to have_been_enqueued.with('subscription.started', result.subscription)
          end

          it 'creates a new subscription' do
            result = create_service.call

            aggregate_failures do
              expect(result).to be_success
              expect(result.subscription.id).not_to eq(subscription.id)
              expect(result.subscription).to be_active
              expect(result.subscription.name).to eq('invoice display name new')
              expect(result.subscription.plan.id).to eq(plan.id)
              expect(result.subscription.previous_subscription_id).to eq(subscription.id)
              expect(result.subscription.subscription_at).to eq(subscription.subscription_at)
            end
          end

          context 'when current subscription is pending' do
            before { subscription.pending! }

            it 'returns existing subscription with updated attributes' do
              result = create_service.call

              aggregate_failures do
                expect(result).to be_success
                expect(result.subscription.id).to eq(subscription.id)
                expect(result.subscription.plan_id).to eq(plan.id)
                expect(result.subscription.name).to eq('invoice display name new')
              end
            end
          end

          context 'when old subscription is payed in arrear' do
            let(:old_plan) { create(:plan, amount_cents: 100, organization:, pay_in_advance: false) }

            it 'enqueues a job to bill the existing subscription' do
              create_service.call
              expect(BillSubscriptionJob).to have_been_enqueued.at_least(1).times
            end
          end

          context 'when old subscription was payed in advance' do
            let(:invoice) do
              create(
                :invoice,
                customer:,
                currency: 'EUR',
                sub_total_excluding_taxes_amount_cents: 100,
                fees_amount_cents: 100,
                taxes_amount_cents: 20,
                total_amount_cents: 120,
              )
            end

            let(:last_subscription_fee) do
              create(
                :fee,
                subscription:,
                invoice:,
                amount_cents: 100,
                taxes_amount_cents: 20,
                invoiceable_type: 'Subscription',
                invoiceable_id: subscription.id,
                taxes_rate: 20,
              )
            end

            let(:subscription) do
              create(
                :subscription,
                customer:,
                plan: old_plan,
                status: :active,
                subscription_at: Time.current - 40.days,
                started_at: Time.current - 40.days,
                external_id:,
                billing_time: 'anniversary',
              )
            end

            let(:old_plan) { create(:plan, amount_cents: 100, organization:, pay_in_advance: true) }

            before { last_subscription_fee }

            it 'creates a credit note for the remaining days' do
              expect { create_service.call }.to change(CreditNote, :count)
            end
          end

          context 'when new subscription is payed in advance' do
            let(:plan) { create(:plan, amount_cents: 200, organization:, pay_in_advance: true) }

            it 'enqueues a job to bill the existing subscription' do
              create_service.call
              expect(BillSubscriptionJob).to have_been_enqueued.at_least(2).times
            end
          end

          context 'with pending next subscription' do
            let(:next_subscription) do
              create(
                :subscription,
                status: :pending,
                previous_subscription: subscription,
                organization: subscription.organization,
              )
            end

            before { next_subscription }

            it 'canceled the next subscription' do
              result = create_service.call

              aggregate_failures do
                expect(result).to be_success
                expect(next_subscription.reload).to be_canceled
              end
            end
          end
        end

        context 'when we downgrade the plan' do
          let(:plan) { create(:plan, amount_cents: 50, organization:) }
          let(:old_plan) { create(:plan, amount_cents: 100, organization:) }
          let(:name) { 'invoice display name new' }

          it 'creates a new subscription' do
            result = create_service.call

            aggregate_failures do
              expect(result).to be_success

              next_subscription = result.subscription.next_subscription
              expect(next_subscription.id).not_to eq(subscription.id)
              expect(next_subscription).to be_pending
              expect(next_subscription.name).to eq('invoice display name new')
              expect(next_subscription.plan_id).to eq(plan.id)
              expect(next_subscription.subscription_at).to eq(subscription.subscription_at)
              expect(next_subscription.previous_subscription).to eq(subscription)
              expect(next_subscription.ending_at).to eq(subscription.ending_at)
            end
          end

          it 'keeps the current subscription' do
            result = create_service.call

            aggregate_failures do
              expect(result.subscription.id).to eq(subscription.id)
              expect(result.subscription).to be_active
              expect(result.subscription.next_subscription).to be_present
            end
          end

          context 'when ending_at is overridden' do
            let(:params) do
              {
                external_customer_id:,
                plan_code:,
                name:,
                external_id:,
                billing_time:,
                subscription_at:,
                subscription_id:,
                ending_at: Time.current.beginning_of_day + 3.months,
              }
            end

            it 'creates a new subscription with correctly set ending_at' do
              result = create_service.call

              aggregate_failures do
                expect(result).to be_success

                next_subscription = result.subscription.next_subscription
                expect(next_subscription.ending_at).to eq(Time.current.beginning_of_day + 3.months)
              end
            end
          end

          context 'when current subscription is pending' do
            before { subscription.pending! }

            it 'returns existing subscription with updated attributes' do
              result = create_service.call

              aggregate_failures do
                expect(result).to be_success
                expect(result.subscription.id).to eq(subscription.id)
                expect(result.subscription.plan_id).to eq(plan.id)
                expect(result.subscription.name).to eq('invoice display name new')
              end
            end
          end

          context 'with pending next subscription' do
            let(:next_subscription) do
              create(
                :subscription,
                status: :pending,
                previous_subscription: subscription,
                organization: subscription.organization,
              )
            end

            before { next_subscription }

            it 'canceled the next subscription' do
              result = create_service.call

              aggregate_failures do
                expect(result).to be_success
                expect(next_subscription.reload).to be_canceled
              end
            end
          end
        end
      end
    end
  end
end
