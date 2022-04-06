# frozen_string_literal: true

class PlansService < BaseService
  def create(**args)
    plan = Plan.new(
      organization_id: args[:organization_id],
      name: args[:name],
      code: args[:code],
      description: args[:description],
      interval: args[:interval].to_sym,
      billing_period: args[:billing_period].to_sym,
      pro_rata: args[:pro_rata],
      pay_in_advance: args[:pay_in_advance],
      amount_cents: args[:amount_cents],
      amount_currency: args[:amount_currency],
      vat_rate: args[:vat_rate],
      trial_period: args[:trial_period],
    )

    # Validates billable metrics
    metric_ids = args[:charges].map { |c| c[:billable_metric_id] }.uniq
    if metric_ids.present? && plan.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
      return result.fail!('unprocessable_entity', 'Billable metrics does not exists')
    end

    ActiveRecord::Base.transaction do
      plan.save!

      args[:charges].each { |c| create_charge(plan, c) }
    end

    result.plan = plan
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail!('unprocessable_entity', e.record.errors.full_messages.join('\n'))
  end

  def update(**args)
    plan = result.user.plans.find_by(id: args[:id])
    return result.fail!('not_found') unless plan

    plan.name = args[:name]
    plan.code = args[:code]
    plan.description = args[:description]
    plan.interval = args[:interval].to_sym
    plan.billing_period = args[:billing_period].to_sym
    plan.pro_rata = args[:pro_rata]
    plan.pay_in_advance = args[:pay_in_advance]
    plan.amount_cents = args[:amount_cents]
    plan.amount_currency = args[:amount_currency]
    plan.vat_rate = args[:vat_rate]
    plan.trial_period = args[:trial_period]

    metric_ids = args[:charges].map { |c| c[:billable_metric_id] }.uniq
    if metric_ids.present? && plan.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
      return result.fail!('unprocessable_entity', 'Billable metrics does not exists')
    end

    ActiveRecord::Base.transaction do
      plan.save!
      created_charges_ids = []

      args[:charges].each do |payload_charge|
        charge = Charge.find_by(id: payload_charge[:id])

        next charge.update(payload_charge) if charge

        created_charge = create_charge(plan, payload_charge)
        created_charges_ids.push(created_charge.id)
      end

      # NOTE: Delete charges that are no more linked to the plan
      sanitize_charges(plan, args[:charges], created_charges_ids)
    end

    result.plan = plan
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail!('unprocessable_entity', e.record.errors.full_messages.join('\n'))
  end

  def destroy(id)
    plan = result.user.plans.find_by(id: id)
    return result.fail!('not_found') unless plan

    plan.destroy!

    result.plan = plan
    result
  end

  private

  def create_charge(plan, args)
    plan.charges.create!(
      billable_metric_id: args[:billable_metric_id],
      amount_cents: args[:amount_cents],
      amount_currency: args[:amount_currency],
      frequency: args[:frequency].to_sym,
      pro_rata: args[:pro_rata],
      vat_rate: args[:vat_rate],
      charge_model: args[:charge_model].to_sym,
    )
  end

  def sanitize_charges(plan, args_charges, created_charges_ids)
    args_charges_ids = args_charges.select { |c| c[:id] != nil }.map { |c| c[:id] }
    charges_ids = plan.charges.pluck(:id) - args_charges_ids - created_charges_ids
    charges_ids.each do |charge_id|
      Charge.find_by(id: charge_id).destroy!
    end
  end
end
