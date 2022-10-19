# frozen_string_literal: true

module Plans
  class CreateService < BaseService
    def create(**args)
      plan = Plan.new(
        organization_id: args[:organization_id],
        name: args[:name],
        code: args[:code],
        description: args[:description],
        parent_id: args[:parent_id],
        interval: args[:interval].to_sym,
        pay_in_advance: args[:pay_in_advance],
        amount_cents: args[:amount_cents],
        amount_currency: args[:amount_currency],
        trial_period: args[:trial_period],
        bill_charges_monthly: args[:interval]&.to_sym == :yearly ? args[:bill_charges_monthly] || false : nil,
      )

      # Validates billable metrics
      if args[:charges].present?
        metric_ids = args[:charges].map { |c| c[:billable_metric_id] }.uniq
        if metric_ids.present? && plan.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
          return result.not_found_failure!(resource: 'billable_metrics')
        end
      end

      ActiveRecord::Base.transaction do
        plan.save!

        args[:charges].each { |c| create_charge(plan, c) } if args[:charges].present?
      end

      result.plan = plan
      track_plan_created(plan)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def create_charge(plan, args)
      plan.charges.create!(
        billable_metric_id: args[:billable_metric_id],
        charge_model: args[:charge_model]&.to_sym,
        properties: args[:properties] || {},
        group_properties: (args[:group_properties] || []).map { |gp| GroupProperty.new(gp) },
      )
    end

    def track_plan_created(plan)
      count_by_charge_model = plan.charges.group(:charge_model).count

      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'plan_created',
        properties: {
          code: plan.code,
          name: plan.name,
          description: plan.description,
          plan_interval: plan.interval,
          plan_amount_cents: plan.amount_cents,
          plan_period: plan.pay_in_advance ? 'advance' : 'arrears',
          trial: plan.trial_period,
          nb_charges: plan.charges.count,
          nb_standard_charges: count_by_charge_model['standard'] || 0,
          nb_percentage_charges: count_by_charge_model['percentage'] || 0,
          nb_graduated_charges: count_by_charge_model['graduated'] || 0,
          nb_package_charges: count_by_charge_model['package'] || 0,
          organization_id: plan.organization_id,
        },
      )
    end
  end
end
