# frozen_string_literal: true

class SubscriptionsService < BaseService
  attr_reader :current_customer, :current_plan

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

    process_create
  end

  # NOTE: Called to terminate a downgraded subscription
  def terminate_and_start_next(subscription:, timestamp:)
    next_subscription = subscription.next_subscription
    return result unless next_subscription
    return result unless next_subscription.pending?

    rotation_date = Time.zone.at(timestamp)

    ActiveRecord::Base.transaction do
      subscription.mark_as_terminated!(rotation_date)
      next_subscription.mark_as_active!(rotation_date)
    end

    # NOTE: Create an invoice for the terminated subscription
    #       if it has not been billed yet
    #       or only for the charges if subscription was billed in advance
    BillSubscriptionJob.perform_later(
      subscription,
      timestamp,
    )

    result.subscription = next_subscription
    return result unless next_subscription.plan.pay_in_advance?

    BillSubscriptionJob.perform_later(
      next_subscription,
      timestamp,
    )

    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  private

  def process_create
    return result.fail!('missing_argument', 'unable to find customer') unless current_customer
    return result.fail!('missing_argument', 'plan does not exists') unless current_plan

    result.subscription = handle_subscription
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  def current_subscription
    @current_subscription ||= current_customer.subscriptions.active.first
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
      anniversary_date: Time.zone.now.to_date,
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
      previous_subscription_id: current_subscription.id,
      anniversary_date: current_subscription.anniversary_date,
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
        previous_subscription_id: current_subscription.id,
        anniversary_date: current_subscription.anniversary_date,
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
end
