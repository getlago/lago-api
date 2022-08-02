# frozen_string_literal: true

module Subscriptions
  class CreateService < BaseService
    attr_reader :current_customer, :current_plan, :current_subscription, :name, :unique_id

    def create_from_api(organization:, params:)
      if params[:customer_id]
        @current_customer = Customer.find_or_create_by!(
          customer_id: params[:customer_id]&.strip,
          organization_id: organization.id,
        )
      end

      @current_plan = Plan.find_by(
        organization_id: organization.id,
        code: params[:plan_code]&.strip,
      )
      @name = params[:name]&.strip
      @unique_id = params[:unique_id]&.strip
      @current_subscription = find_current_subscription(params[:subscription_id])

      process_create
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def create(**args)
      @current_customer = Customer.find_by(
        id: args[:customer_id],
        organization_id: args[:organization_id],
      )

      @current_plan = Plan.find_by(
        organization_id: args[:organization_id],
        id: args[:plan_id]&.strip,
      )
      @name = args[:name]&.strip
      @unique_id = SecureRandom.uuid
      @current_subscription = find_current_subscription(args[:subscription_id])

      process_create
    end

    private

    def process_create
      return result.fail!('missing_argument', 'unable to find customer') unless current_customer
      return result.fail!('missing_argument', 'plan does not exists') unless current_plan

      if currency_missmatch?(current_customer&.active_subscription&.plan, current_plan)
        return result.fail!('currencies_does_not_match', 'currencies does not match')
      end


      result.subscription = handle_subscription
      track_subscription_created(result.subscription)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def find_current_subscription(subscription_id)
      current_customer&.active_subscriptions&.find_by(id: subscription_id)
    end

    def handle_subscription
      return upgrade_subscription if upgrade?
      return downgrade_subscription if downgrade?

      existing_subscription || create_subscription
    end

    def upgrade?
      return false unless current_subscription
      return false if current_plan.id == current_subscription.plan.id

      current_plan.yearly_amount_cents >= current_subscription.plan.yearly_amount_cents
    end

    def downgrade?
      return false unless current_subscription
      return false if current_plan.id == current_subscription.plan.id

      current_plan.yearly_amount_cents < current_subscription.plan.yearly_amount_cents
    end

    def create_subscription
      new_subscription = Subscription.new(
        customer: current_customer,
        plan_id: current_plan.id,
        subscription_date: Time.zone.now.to_date,
        name: name,
        unique_id: unique_id
      )
      new_subscription.mark_as_active!

      if current_plan.pay_in_advance?
        BillSubscriptionJob.perform_later(
          new_subscription,
          Time.zone.now.to_i,
        )
      end

      new_subscription
    end

    def upgrade_subscription
      new_subscription = Subscription.new(
        customer: current_customer,
        plan: current_plan,
        name: name,
        unique_id: current_subscription.unique_id,
        previous_subscription_id: current_subscription.id,
        subscription_date: current_subscription.subscription_date,
      )

      ActiveRecord::Base.transaction do
        cancel_pending_subscription if pending_subscription?

        # NOTE: When upgrading, the new subscription becomes active immediatly
        #       The previous one must be terminated
        current_subscription.mark_as_terminated!
        new_subscription.mark_as_active!
      end

      if current_subscription.plan.pay_in_arrear?
        BillSubscriptionJob.perform_later(
          current_subscription,
          Time.zone.now.to_i,
        )
      end

      if current_plan.pay_in_advance?
        BillSubscriptionJob.perform_later(
          new_subscription,
          Time.zone.now.to_i,
        )
      end

      new_subscription
    end

    def downgrade_subscription
      ActiveRecord::Base.transaction do
        cancel_pending_subscription if pending_subscription?

        # NOTE: When downgrading a subscription, we keep the current one active
        #       until the next billing day. The new subscription will become active at this date
        Subscription.create!(
          customer: current_customer,
          plan: current_plan,
          name: name,
          unique_id: current_subscription.unique_id,
          previous_subscription_id: current_subscription.id,
          subscription_date: current_subscription.subscription_date,
          status: :pending,
        )
      end

      current_subscription
    end

    def pending_subscription?
      return false unless current_subscription&.next_subscription

      current_subscription.next_subscription.pending?
    end

    def cancel_pending_subscription
      current_subscription.next_subscription.mark_as_canceled!
    end

    def subscription_type
      return 'downgrade' if downgrade?
      return 'upgrade' if upgrade?

      'create'
    end

    def track_subscription_created(subscription)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'subscription_created',
        properties: {
          created_at: subscription.created_at,
          customer_id: subscription.customer_id,
          plan_code: subscription.plan.code,
          plan_name: subscription.plan.name,
          subscription_type: subscription_type,
          organization_id: subscription.organization.id
        }
      )
    end

    def currency_missmatch?(old_plan, new_plan)
      return false unless old_plan

      old_plan.amount_currency != new_plan.amount_currency
    end

    def existing_subscription
      @existing_subscription ||= Subscription.active.find_by(unique_id: unique_id, customer_id: current_customer.id)
    end
  end
end
