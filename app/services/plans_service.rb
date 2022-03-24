# frozen_string_literal: true

class PlansService < BaseService
  include ScopedToOrganization

  def create(**args)
    return result.fail!('not_organization_member') unless organization_member?(args[:organization_id])

    plan = Plan.new(
      organization_id: args[:organization_id],
      name: args[:name],
      code: args[:code],
      description: args[:description],
      frequency: args[:frequency].to_sym,
      billing_period: args[:billing_period].to_sym,
      pro_rata: args[:pro_rata],
      amount_cents: args[:amount_cents],
      currency: args[:currency],
      vat_rate: args[:vat_rate],
      trial_period: args[:trial_period]
    )

    # TODO: create charges
    # Validates billable metrics
    metric_ids = args[:billable_metric_ids]
    if metric_ids.present? && plan.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
      return result.fail!('unprocessable_entity', 'Billable metrics does not exists')
    end

    ActiveRecord::Base.transaction do
      # TODO: better handling of validation errors
      plan.save!

      plan.billable_metric_ids = metric_ids if metric_ids.present?
    end

    result.plan = plan
    result
  end

  def update(**args)
    plan = Plan.find_by(id: args[:id])
    return result.fail!('not_found') unless plan
    return result.fail!('not_organization_member') unless organization_member?(plan.organization_id)

    plan.name = args[:name]
    plan.code = args[:code]
    plan.description = args[:description]
    plan.frequency = args[:frequency].to_sym
    plan.billing_period = args[:billing_period].to_sym
    plan.pro_rata = args[:pro_rata]
    plan.amount_cents = args[:amount_cents]
    plan.currency = args[:currency]
    plan.vat_rate = args[:vat_rate]
    plan.trial_period = args[:trial_period]

    # TODO: create charges
    metric_ids = args[:billable_metric_ids]
    if metric_ids.present? && plan.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
      return result.fail!('unprocessable_entity', 'Billable metrics does not exists')
    end

    ActiveRecord::Base.transaction do
      # TODO: better handling of validation errors
      plan.save!

      plan.billable_metric_ids = metric_ids if metric_ids.present?
    end

    result.plan = plan
    result
  end

  def destroy(id)
    plan = Plan.find_by(id: id)
    return result.fail!('not_found') unless plan
    return result.fail!('not_organization_member') unless organization_member?(plan.organization_id)

    plan.destroy!

    result.plan = plan
    result
  end
end
