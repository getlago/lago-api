# frozen_string_literal: true

module Plans
  class UpdateService < BaseService
    def update(**args)
      plan = result.user.plans.find_by(id: args[:id])
      return result.fail!('not_found') unless plan

      plan.name = args[:name]
      plan.description = args[:description]

      # NOTE: Only name and description are editable if plan
      #       is attached to subscriptions
      unless plan.attached_to_subscriptions?
        plan.code = args[:code]
        plan.interval = args[:interval].to_sym
        plan.pay_in_advance = args[:pay_in_advance]
        plan.amount_cents = args[:amount_cents]
        plan.amount_currency = args[:amount_currency]
        plan.trial_period = args[:trial_period]
        plan.bill_charges_monthly = args[:interval].to_sym == :yearly ? args[:bill_charges_monthly] || false : nil
      end

      metric_ids = args[:charges].map { |c| c[:billable_metric_id] }.uniq
      if metric_ids.present? && plan.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
        return result.fail!('not_found', 'Billable metrics does not exists')
      end

      ActiveRecord::Base.transaction do
        plan.save!

        process_charges(plan, args[:charges])
      end

      result.plan = plan
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    def update_from_api(organization:, code:, params:)
      plan = organization.plans.find_by(code: code)
      return result.fail!('not_found', 'plan does not exist') unless plan

      plan.name = params[:name] if params.key?(:name)
      plan.description = params[:description] if params.key?(:description)

      unless plan.attached_to_subscriptions?
        plan.code = params[:code] if params.key?(:code)
        plan.interval = params[:interval].to_sym if params.key?(:interval)
        plan.pay_in_advance = params[:pay_in_advance] if params.key?(:pay_in_advance)
        plan.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
        plan.amount_currency = params[:amount_currency] if params.key?(:amount_currency)
        plan.trial_period = params[:trial_period] if params.key?(:trial_period)
        plan.bill_charges_monthly = params[:interval]&.to_sym == :yearly ? params[:bill_charges_monthly] || false : nil
      end

      unless params[:charges].blank?
        metric_ids = params[:charges].map { |c| c[:billable_metric_id] }.uniq
        if metric_ids.present? && plan.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
          return result.fail!('not_found', 'plan does not exists')
        end
      end

      ActiveRecord::Base.transaction do
        plan.save!

        process_charges(plan, params[:charges] || [])
      end

      result.plan = plan
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    def create_charge(plan, args)
      plan.charges.create!(
        billable_metric_id: args[:billable_metric_id],
        amount_currency: args[:amount_currency],
        charge_model: args[:charge_model]&.to_sym,
        properties: args[:properties] || {},
      )
    end

    def process_charges(plan, params_charges)
      created_charges_ids = []

      hash_charges = params_charges.map { |c| c.to_h.deep_symbolize_keys }
      hash_charges.each do |payload_charge|
        charge = Charge.find_by(id: payload_charge[:id])

        if charge
          # NOTE: charges cannot be edited if plan is attached to a subscription
          charge.update(payload_charge) unless plan.attached_to_subscriptions?
          next
        end

        created_charge = create_charge(plan, payload_charge)
        created_charges_ids.push(created_charge.id)
      end

      # NOTE: Delete charges that are no more linked to the plan
      sanitize_charges(plan, hash_charges, created_charges_ids)
    end

    def sanitize_charges(plan, args_charges, created_charges_ids)
      args_charges_ids = args_charges.reject { |c| c[:id].nil? }.map { |c| c[:id] }
      charges_ids = plan.charges.pluck(:id) - args_charges_ids - created_charges_ids
      charges_ids.each do |charge_id|
        Charge.find_by(id: charge_id).destroy!
      end
    end
  end
end
