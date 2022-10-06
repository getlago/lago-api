# frozen_string_literal: true

module Subscriptions
  class CreateService < BaseService
    attr_reader(
      :current_customer,
      :current_plan,
      :current_subscription,
      :name,
      :external_id,
      :billing_time,
      :subscription_date,
    )

    def create_from_api(organization:, params:)
      if params[:external_customer_id]
        @current_customer = Customer.find_or_create_by!(
          external_id: params[:external_customer_id]&.strip,
          organization_id: organization.id,
        )
      end

      # NOTE: prepare subscription attributes
      @current_plan = Plan.find_by(
        organization_id: organization.id,
        code: params[:plan_code]&.strip,
      )
      @name = params[:name]&.strip
      @external_id = params[:external_id]&.strip
      @billing_time = params[:billing_time]
      @subscription_date = params[:subscription_date] || Time.current.to_date
      @current_subscription = editable_subscriptions&.find_by(external_id: external_id)

      process_create
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
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

      # NOTE: prepare subscription attributes
      @name = args[:name]&.strip
      @external_id = SecureRandom.uuid
      @billing_time = args[:billing_time]
      @subscription_date = args[:subscription_date] || Time.current.to_date
      @current_subscription = editable_subscriptions&.find_by(id: args[:subscription_id])

      process_create
    end

    private

    def process_create
      return result unless valid?(customer: current_customer, plan: current_plan, subscription_date: subscription_date)

      ActiveRecord::Base.transaction do
        currency_result = Customers::UpdateService.new(nil).update_currency(
          customer: current_customer,
          currency: current_plan.amount_currency,
        )
        return currency_result unless currency_result.success?

        result.subscription = handle_subscription
      end

      track_subscription_created(result.subscription)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ArgumentError
      result.validation_failure!(errors: { billing_time: ['value_is_invalid'] })
    end

    def valid?(args)
      Subscriptions::ValidateService.new(result, **args).valid?
    end

    def handle_subscription
      return upgrade_subscription if upgrade?
      return downgrade_subscription if downgrade?

      current_subscription || create_subscription
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
        subscription_date: subscription_date,
        name: name,
        external_id: external_id,
        billing_time: billing_time || :calendar,
      )

      if new_subscription.subscription_date > Time.current.to_date
        new_subscription.pending!
      elsif new_subscription.subscription_date < Time.current.to_date
        new_subscription.mark_as_active!(new_subscription.subscription_date.beginning_of_day)
      else
        new_subscription.mark_as_active!
      end

      if current_plan.pay_in_advance? && new_subscription.subscription_date.today?
        # NOTE: Since job is laucnhed from inside a db transaction
        #       we must wait for it to be commited before processing the job
        BillSubscriptionJob
          .set(wait: 2.seconds)
          .perform_later(
            [new_subscription],
            Time.zone.now.to_i,
          )
      end

      new_subscription
    end

    def upgrade_subscription
      if current_subscription.starting_in_the_future?
        current_subscription.plan = current_plan
        current_subscription.name = name if name.present?
        current_subscription.save!

        return current_subscription
      end

      new_subscription = Subscription.new(
        customer: current_customer,
        plan: current_plan,
        name: name,
        external_id: current_subscription.external_id,
        previous_subscription_id: current_subscription.id,
        subscription_date: current_subscription.subscription_date,
        billing_time: current_subscription.billing_time,
      )

      cancel_pending_subscription if pending_subscription?

      # NOTE: When upgrading, the new subscription becomes active immediatly
      #       The previous one must be terminated
      current_subscription.mark_as_terminated!
      new_subscription.mark_as_active!

      if current_subscription.plan.pay_in_arrear?
        # NOTE: Since job is laucnhed from inside a db transaction
        #       we must wait for it to be commited before processing the job
        BillSubscriptionJob
          .set(wait: 2.seconds)
          .perform_later(
            [current_subscription],
            Time.zone.now.to_i,
          )
      end

      if current_plan.pay_in_advance?
        # NOTE: Since job is laucnhed from inside a db transaction
        #       we must wait for it to be commited before processing the job
        BillSubscriptionJob
          .set(wait: 2.seconds)
          .perform_later(
            [new_subscription],
            Time.zone.now.to_i,
          )
      end

      new_subscription
    end

    def downgrade_subscription
      if current_subscription.starting_in_the_future?
        current_subscription.plan = current_plan
        current_subscription.name = name if name.present?
        current_subscription.save!

        return current_subscription
      end

      cancel_pending_subscription if pending_subscription?

      # NOTE: When downgrading a subscription, we keep the current one active
      #       until the next billing day. The new subscription will become active at this date
      Subscription.create!(
        customer: current_customer,
        plan: current_plan,
        name: name,
        external_id: current_subscription.external_id,
        previous_subscription_id: current_subscription.id,
        subscription_date: current_subscription.subscription_date,
        status: :pending,
        billing_time: current_subscription.billing_time,
      )

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
          organization_id: subscription.organization.id,
          billing_time: subscription.billing_time,
        },
      )
    end

    def currency_missmatch?(old_plan, new_plan)
      return false unless old_plan

      old_plan.amount_currency != new_plan.amount_currency
    end

    def editable_subscriptions
      @editable_subscriptions ||= current_customer&.editable_subscriptions
    end
  end
end
