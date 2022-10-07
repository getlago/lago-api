# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::CreateService, type: :service do
  subject(:create_service) { described_class.new }

  let(:organization) { create(:organization) }

  describe '.create_from_api' do
    let(:plan) { create(:plan, amount_cents: 100, organization: organization) }
    let(:customer) { create(:customer, organization: organization) }
    let(:external_id) { SecureRandom.uuid }

    let(:params) do
      {
        external_customer_id: customer.external_id,
        plan_code: plan.code,
        name: 'invoice display name',
        external_id: external_id,
        billing_time: 'anniversary',
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a subscription with subscription date set to current date' do
      result = create_service.create_from_api(
        organization: organization,
        params: params,
      )

      expect(result).to be_success

      subscription = result.subscription

      aggregate_failures do
        expect(subscription.customer_id).to eq(customer.id)
        expect(subscription.plan_id).to eq(plan.id)
        expect(subscription.started_at).to be_present
        expect(subscription.subscription_date).to be_present
        expect(subscription.name).to eq('invoice display name')
        expect(subscription).to be_active
        expect(subscription.external_id).to eq(external_id)
        expect(subscription).to be_anniversary
      end
    end

    it 'calls SegmentTrackJob' do
      subscription = create_service.create_from_api(
        organization: organization,
        params: params,
      ).subscription

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

    context 'when external_id is not given' do
      let(:external_id) { nil }

      it 'returns an error' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        expect(result).not_to be_success
        expect(result.error.messages[:external_id]).to eq(['value_is_mandatory'])
      end
    end

    context 'when billing_time is not provided' do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          plan_code: plan.code,
          name: 'invoice display name',
          external_id: external_id,
        }
      end

      it 'creates a calendar subscription' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        aggregate_failures do
          expect(result).to be_success

          expect(result.subscription).to be_calendar
        end
      end
    end

    context 'when customer does not exists' do
      let(:params) do
        {
          external_customer_id: SecureRandom.uuid,
          plan_code: plan.code,
          external_id: external_id,
        }
      end

      it 'creates a customer' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        expect(result).to be_success

        subscription = result.subscription

        aggregate_failures do
          expect(subscription.customer.external_id).to eq(params[:external_customer_id])
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at).to be_present
          expect(subscription.subscription_date).to be_present
          expect(subscription).to be_active
        end
      end

      context 'when plan is pay_in_advance and subscription_date is current date' do
        before { plan.update(pay_in_advance: true) }

        it 'enqueued a job to bill the subscription' do
          expect do
            create_service.create_from_api(
              organization: organization,
              params: params,
            )
          end.to have_enqueued_job(BillSubscriptionJob)
        end
      end

      context 'when plan is pay_in_advance and subscription_date is in the future' do
        let(:params) do
          {
            external_customer_id: customer.external_id,
            plan_code: plan.code,
            name: 'invoice display name',
            external_id: external_id,
            billing_time: 'anniversary',
            subscription_date: (Time.current + 5.days).to_date,
          }
        end

        before { plan.update(pay_in_advance: true) }

        it 'did not enqueue a job to bill the subscription' do
          expect do
            create_service.create_from_api(
              organization: organization,
              params: params,
            )
          end.not_to have_enqueued_job(BillSubscriptionJob)
        end
      end
    end

    context 'when external customer id is missing' do
      let(:params) do
        {
          external_customer_id: nil,
          plan_code: plan.code,
          external_id: external_id,
        }
      end

      it 'returns a customer_not_found error' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('customer_not_found')
        end
      end
    end

    context 'when plan does not exists' do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          plan_code: 'invalid_plan',
          external_id: external_id,
        }
      end

      it 'returns a plan_not_found error' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('plan_not_found')
        end
      end
    end

    context 'when subscription_date is given and is invalid' do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          plan_code: plan.code,
          name: 'invoice display name',
          external_id: external_id,
          billing_time: 'anniversary',
          subscription_date: '2022-99-99',
        }
      end

      it 'returns invalid_date error' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.messages[:subscription_date]).to eq(['invalid_date'])
        end
      end
    end

    context 'when subscription_date is given and is in the future' do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          plan_code: plan.code,
          name: 'invoice display name',
          external_id: external_id,
          billing_time: 'anniversary',
          subscription_date: (Time.current + 5.days).to_date,
        }
      end

      it 'creates a pending subscription' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        expect(result).to be_success

        subscription = result.subscription

        aggregate_failures do
          expect(subscription.customer_id).to eq(customer.id)
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at).not_to be_present
          expect(subscription.subscription_date).to eq((Time.current + 5.days).to_date)
          expect(subscription.name).to eq('invoice display name')
          expect(subscription).to be_pending
          expect(subscription.external_id).to eq(external_id)
          expect(subscription).to be_anniversary
        end
      end
    end

    context 'when subscription_date is given and is in the past' do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          plan_code: plan.code,
          name: 'invoice display name',
          external_id: external_id,
          billing_time: 'anniversary',
          subscription_date: (Time.current - 5.days).to_date,
        }
      end

      it 'creates a active subscription' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        expect(result).to be_success

        subscription = result.subscription

        aggregate_failures do
          expect(subscription.customer_id).to eq(customer.id)
          expect(subscription.plan_id).to eq(plan.id)
          expect(subscription.started_at).to eq((Time.current - 5.days).beginning_of_day)
          expect(subscription.subscription_date).to eq((Time.current - 5.days).to_date)
          expect(subscription.name).to eq('invoice display name')
          expect(subscription).to be_active
          expect(subscription.external_id).to eq(external_id)
          expect(subscription).to be_anniversary
        end
      end
    end

    context 'when billing_time is invalid' do
      let(:params) do
        {
          external_customer_id: customer.id,
          plan_code: plan.code,
          external_id: external_id,
          billing_time: :foo,
        }
      end

      it 'fails' do
        result = create_service.create_from_api(
          organization: organization,
          params: params,
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to eq([:billing_time])
        end
      end
    end

    context 'when an active subscription already exists' do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          plan_code: plan.code,
          name: 'invoice display name',
          external_id: external_id,
        }
      end
      let(:subscription) do
        create(
          :subscription,
          customer: customer,
          plan: plan,
          status: :active,
          subscription_date: Time.zone.now.to_date,
          started_at: Time.zone.now,
        )
      end

      before { subscription }

      context 'when external_id is given' do
        let(:params) do
          {
            external_customer_id: customer.external_id,
            plan_code: plan.code,
            name: 'invoice display name',
            external_id: external_id,
          }
        end

        it 'returns existing subscription' do
          subscription.update!(external_id: external_id)

          result = create_service.create_from_api(
            organization: organization,
            params: params,
          )

          expect(result).to be_success
          expect(result.subscription.id).to eq(subscription.id)
        end
      end

      context 'when new plan has different currency than the old plan' do
        let(:new_plan) { create(:plan, amount_cents: 200, organization: organization, amount_currency: 'USD') }
        let(:params) do
          {
            external_customer_id: customer.external_id,
            plan_code: new_plan.code,
            name: 'invoice display name new',
            external_id: external_id,
          }
        end

        before { customer.update!(currency: plan.amount_currency) }

        it 'fails' do
          result = create_service.create_from_api(
            organization: organization,
            params: params,
          )

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
          let(:higher_plan) { create(:plan, amount_cents: 200, organization: organization) }
          let(:params) do
            {
              external_customer_id: customer.external_id,
              plan_code: higher_plan.code,
              name: 'invoice display name new',
              external_id: subscription.external_id,
            }
          end

          it 'terminates the existing subscription' do
            create_service.create_from_api(
              organization: organization,
              params: params,
            )

            old_subscription = Subscription.find(subscription.id)

            expect(old_subscription).to be_terminated
          end

          it 'creates a new subscription' do
            result = create_service.create_from_api(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result).to be_success
              expect(result.subscription.id).not_to eq(subscription.id)
              expect(result.subscription).to be_active
              expect(result.subscription.name).to eq('invoice display name new')
              expect(result.subscription.plan.id).to eq(higher_plan.id)
              expect(result.subscription.previous_subscription_id).to eq(subscription.id)
              expect(result.subscription.subscription_date).to eq(subscription.subscription_date)
            end
          end

          context 'when current subscription is pending' do
            before { subscription.pending! }

            it 'returns existing subscription with updated attributes' do
              result = create_service.create_from_api(
                organization: organization,
                params: params,
              )

              aggregate_failures do
                expect(result).to be_success
                expect(result.subscription.id).to eq(subscription.id)
                expect(result.subscription.plan_id).to eq(higher_plan.id)
                expect(result.subscription.name).to eq('invoice display name new')
              end
            end
          end

          context 'when old subscription is payed in arrear' do
            before { plan.update!(pay_in_advance: false) }

            it 'enqueues a job to bill the existing subscription' do
              expect do
                create_service.create_from_api(
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
                create_service.create_from_api(
                  organization: organization,
                  params: params,
                )
              end.to have_enqueued_job(BillSubscriptionJob)
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
              result = create_service.create_from_api(
                organization: organization,
                params: params,
              )

              aggregate_failures do
                expect(result).to be_success
                expect(next_subscription.reload).to be_canceled
              end
            end
          end
        end

        context 'when we downgrade the plan' do
          let(:lower_plan) do
            create(:plan, amount_cents: 50, organization: organization)
          end

          let(:params) do
            {
              external_customer_id: customer.external_id,
              plan_code: lower_plan.code,
              name: 'invoice display name new',
              external_id: subscription.external_id,
            }
          end

          it 'creates a new subscription' do
            result = create_service.create_from_api(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result).to be_success

              next_subscription = result.subscription.next_subscription
              expect(next_subscription.id).not_to eq(subscription.id)
              expect(next_subscription).to be_pending
              expect(next_subscription.name).to eq('invoice display name new')
              expect(next_subscription.plan_id).to eq(lower_plan.id)
              expect(next_subscription.subscription_date).to eq(subscription.subscription_date)
              expect(next_subscription.previous_subscription).to eq(subscription)
            end
          end

          it 'keeps the current subscription' do
            result = create_service.create_from_api(
              organization: organization,
              params: params,
            )

            aggregate_failures do
              expect(result.subscription.id).to eq(subscription.id)
              expect(result.subscription).to be_active
              expect(result.subscription.next_subscription).to be_present
            end
          end

          context 'when current subscription is pending' do
            before { subscription.pending! }

            it 'returns existing subscription with updated attributes' do
              result = create_service.create_from_api(
                organization: organization,
                params: params,
              )

              aggregate_failures do
                expect(result).to be_success
                expect(result.subscription.id).to eq(subscription.id)
                expect(result.subscription.plan_id).to eq(lower_plan.id)
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
              result = create_service.create_from_api(
                organization: organization,
                params: params,
              )

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

  describe '.create' do
    let(:plan) { create(:plan, amount_cents: 100, organization: organization) }
    let(:customer) { create(:customer, organization: organization) }

    let(:params) do
      {
        customer_id: customer.id,
        plan_id: plan.id,
        organization_id: organization.id,
        billing_time: :anniversary,
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it 'creates a subscription' do
      result = create_service.create(**params)

      expect(result).to be_success

      subscription = result.subscription

      aggregate_failures do
        expect(subscription.customer_id).to eq(customer.id)
        expect(subscription.plan_id).to eq(plan.id)
        expect(subscription.started_at).to be_present
        expect(subscription.subscription_date).to be_present
        expect(subscription).to be_active
        expect(subscription).to be_anniversary
      end
    end

    it 'calls SegmentTrackJob' do
      subscription = create_service.create(**params).subscription

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

    context 'when customer does not exists' do
      let(:params) do
        {
          customer_id: SecureRandom.uuid,
          plan_code: plan.id,
          organization_id: organization.id,
        }
      end

      it 'returns a customer_not_found error' do
        result = create_service.create(**params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('customer_not_found')
        end
      end
    end

    context 'when plan doest not exists' do
      let(:params) do
        {
          customer_id: customer.id,
          plan_code: 'invalid_plan',
          organization_id: organization.id,
        }
      end

      it 'returns a plan_not_found error' do
        result = create_service.create(**params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq('plan_not_found')
        end
      end
    end

    context 'when subscription_date is given and is invalid' do
      let(:params) do
        {
          customer_id: customer.id,
          plan_id: plan.id,
          organization_id: organization.id,
          billing_time: :anniversary,
          subscription_date: '2022-99-99',
        }
      end

      it 'returns invalid_date error' do
        result = create_service.create(**params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.messages[:subscription_date]).to eq(['invalid_date'])
        end
      end
    end

    context 'when billing_time is invalid' do
      let(:params) do
        {
          customer_id: customer.id,
          plan_id: plan.id,
          organization_id: organization.id,
          billing_time: :foo,
        }
      end

      it 'fails' do
        result = create_service.create(**params)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to eq([:billing_time])
        end
      end
    end
  end
end
