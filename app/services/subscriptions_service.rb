# frozen_string_literal: true

class SubscriptionsService < BaseService
  def create(organization:, params:)
    unless current_customer(organization.id, params[:customer_id]&.strip)
      return result.fail!('missing_argument', 'unable to find customer')
    end

    unless current_plan(organization.id, params[:plan_code])
      return result.fail!('missing_argument', 'plan does not exists')
    end

    handle_current_subscription if current_subscription.present?

    new_subscription = Subscription.find_or_initialize_by(
      customer: current_customer,
      status: :active,
      plan_id: current_plan.id,
    )

    # NOTE: If the subscription already exists (so its the same as the current_subscription)
    #       We do not create a new one and simply return it into the result.
    process_new_subscription(new_subscription) if new_subscription.new_record?

    result.subscription = new_subscription
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

  def handle_current_subscription
    return if current_plan.id == current_subscription.plan.id

    # NOTE: We Upgrade the subscription
    if current_plan.amount_cents >= current_subscription.plan.amount_cents
      current_subscription.mark_as_terminated!

      BillSubscriptionJob.perform_later(
        subscription: current_subscription,
        timestamp: Time.zone.now.to_i,
      )
    end

    # TODO: Downgrade
  end
end
