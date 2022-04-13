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

  def process_new_subscription(new_subscription)
    new_subscription.previous_subscription_id = current_subscription.id if current_subscription.present?

    new_subscription.mark_as_active!

    return unless current_plan.pay_in_advance?

    BillSubscriptionJob.perform_later(
      subscription: new_subscription,
      timestamp: Time.zone.now.to_i,
    )
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

    current_plan.amount_cents <= current_subscription.plan.amount_cents
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
        subscription: new_subscription,
        timestamp: Time.zone.now.to_i,
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

    BillSubscriptionJob.perform_later(
      subscription: current_subscription,
      timestamp: Time.zone.now.to_i,
    )

    if current_plan.pay_in_advance?
      BillSubscriptionJob.perform_later(
        subscription: new_subscription,
        timestamp: Time.zone.now.to_i,
      )
    end

    new_subscription
  end

  def downgrade_subscription
    new_subscription = Subscription.new(
      customer: current_customer,
      plan: current_plan,
      previous_subscription_id: current_subscription.id,
      anniversary_date: current_subscription.anniversary_date,
    )

    if current_subscription.plan.pay_in_advance?
      # NOTE: When downgrading a payed in advance subscription, we keep the current one active
      #       until the next billing day. The new subscription will become active at this date
      new_subscription.pending!

      return current_subscription
    else
      # NOTE: When downgrading a payed in arrear subscription, the new one becomes active immediatly
      #       the previous one must be terminated and billed using the pro-rata
      ActiveRecord::Base.transaction do
        new_subscription.mark_as_active!
        current_subscription.mark_as_terminated!
      end

      BillSubscriptionJob.perform_later(
        subscription: current_subscription,
        timestamp: Time.zone.now.to_i,
      )
    end

    new_subscription
  end
end
