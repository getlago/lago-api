# frozen_string_literal: true

class SubscriptionsService < BaseService
  def create(organization:, params:)
    unless current_customer(organization.id, params[:customer_id])
      return result.fail!('missing_argument', 'customer does not exists')
    end

    unless current_plan(organization.id, params[:plan_code])
      return result.fail!('missing_argument', 'plan does not exists')
    end

    # TODO: Handle customers with existing plans
    subscription = current_customer.subscriptions.find_or_initialize_by(
      plan_id: current_plan.id
    )
    subscription.mark_as_active!

    result.subscription = subscription
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
  end

  private

  def current_customer(organization_id = nil, customer_id = nil)
    @current_customer ||= Customer.find_by(
      customer_id: customer_id,
      organization_id: organization_id
    )
  end

  def current_plan(organization_id = nil, code = nil)
    @current_plan ||= Plan.find_by(
      code: code,
      organization_id: organization_id
    )
  end
end
