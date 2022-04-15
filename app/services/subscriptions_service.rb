# frozen_string_literal: true

class SubscriptionsService < BaseService
  def create(organization:, params:)
    unless current_customer(organization.id, params[:customer_id]&.strip)
      return result.fail!('missing_argument', 'unable to find customer')
    end

    unless current_plan(organization.id, params[:plan_code])
      return result.fail!('missing_argument', 'plan does not exists')
    end

    result.subscription = handle_subscription
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

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
    if subscription.plan.pay_in_arrear?
      BillSubscriptionJob.perform_later(
        subscription,
        timestamp,
      )
    end

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

  def current_customer(organization_id = nil, customer_id = nil)
    return @current_customer if @current_customer
    return unless customer_id

    @current_customer = Customer.find_or_create_by!(
      customer_id: customer_id,
      organization_id: organization_id,
    )
  end

  def current_plan(organization_id = nil, code = nil)
    @current_plan ||= Plan.find_by(
      code: code,
      organization_id: organization_id,
    )
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

    current_plan.amount_cents >= current_subscription.plan.amount_cents
  end

  def downgrade?
    return false unless current_subscription
    return false if current_plan.id == current_subscription.plan.id

    current_plan.amount_cents < current_subscription.plan.amount_cents
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
    # NOTE: When downgrading a subscription, we keep the current one active
    #       until the next billing day. The new subscription will become active at this date
    Subscription.create!(
      customer: current_customer,
      plan: current_plan,
      previous_subscription_id: current_subscription.id,
      anniversary_date: current_subscription.anniversary_date,
      status: :pending,
    )

    current_subscription
  end
end
