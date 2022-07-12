# frozen_string_literal: true

module Plans
  class CreateService < BaseService
    def create(**args)
      plan = Plan.new(
        organization_id: args[:organization_id],
        name: args[:name],
        code: args[:code],
        description: args[:description],
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
          return result.fail!('not_found', 'Billable metrics does not exists')
        end
      end

      ActiveRecord::Base.transaction do
        plan.save!

        args[:charges].each { |c| create_charge(plan, c) } if args[:charges].present?
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
  end
end
