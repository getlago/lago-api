# frozen_string_literal: true

module Plans
  class UpdateService < BaseService
    def initialize(plan:, params:)
      @plan = plan
      @params = params
      super
    end

    activity_loggable(
      action: "plan.updated",
      record: -> { plan },
      condition: -> { plan&.parent_id.nil? }
    )

    def call
      return result.not_found_failure!(resource: "plan") unless plan

      old_amount_cents = plan.amount_cents

      plan.name = params[:name] if params.key?(:name)
      plan.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      plan.description = params[:description] if params.key?(:description)
      plan.amount_cents = params[:amount_cents] if params.key?(:amount_cents)

      # NOTE: If plan is attached to subscriptions the editable attributes are:
      #       name, invoice_display_name, description, amount_cents
      unless plan.attached_to_subscriptions?
        plan.code = params[:code] if params.key?(:code)
        plan.interval = params[:interval].to_sym if params.key?(:interval)
        plan.pay_in_advance = params[:pay_in_advance] if params.key?(:pay_in_advance)
        plan.amount_currency = params[:amount_currency] if params.key?(:amount_currency)
        plan.trial_period = params[:trial_period] if params.key?(:trial_period)
        plan.bill_charges_monthly = bill_charges_monthly?
      end

      if params[:charges].present?
        metric_ids = params[:charges].map { |c| c[:billable_metric_id] }.uniq
        if metric_ids.present? && organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
          return result.not_found_failure!(resource: "billable_metrics")
        end
      end

      ActiveRecord::Base.transaction do
        plan.save!

        if params[:tax_codes]
          taxes_result = Plans::ApplyTaxesService.call(plan:, tax_codes: params[:tax_codes])
          taxes_result.raise_if_error!
        end

        process_charges(plan, params[:charges]) if params[:charges]

        if params.key?(:usage_thresholds) && License.premium?
          Plans::UpdateUsageThresholdsService.call(plan:, usage_thresholds_params: params[:usage_thresholds])
        end

        process_minimum_commitment(plan, params[:minimum_commitment]) if params[:minimum_commitment] && License.premium?

        if old_amount_cents != plan.amount_cents
          process_downgraded_subscriptions
          process_pending_subscriptions
        end
      end

      cascade_subscription_fee_update(old_amount_cents)

      plan.invoices.draft.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations

      SendWebhookJob.perform_after_commit("plan.updated", plan)
      result.plan = plan.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :plan, :params

    delegate :organization, to: :plan

    def bill_charges_monthly?
      return unless params[:interval]&.to_sym == :yearly

      params[:bill_charges_monthly] || false
    end

    def cascade_subscription_fee_update(old_amount_cents)
      return unless cascade?
      return if old_amount_cents == plan.amount_cents
      return if plan.children.empty?

      plan.children.where(amount_cents: old_amount_cents).find_each do |p|
        Plans::UpdateAmountJob.perform_later(plan: p, amount_cents: plan.amount_cents, expected_amount_cents: old_amount_cents)
      end
    end

    def cascade_charge_creation(charge, payload_charge)
      return unless cascade?
      return if plan.children.empty?

      Charges::CreateChildrenJob.perform_later(charge:, payload: payload_charge)
    end

    def cascade_charge_removal(charge)
      return unless cascade?
      return if plan.children.empty?

      Charges::DestroyChildrenJob.perform_later(charge.id)
    end

    def cascade_charge_update(charge, payload_charge)
      return unless cascade?
      return if plan.children.empty?

      old_parent_attrs = charge.attributes
      old_parent_filters_attrs = charge.filters.map(&:attributes)
      old_parent_applied_pricing_unit_attrs = charge.applied_pricing_unit&.attributes

      Charges::UpdateChildrenJob.perform_later(
        params: payload_charge.deep_stringify_keys,
        old_parent_attrs:,
        old_parent_filters_attrs:,
        old_parent_applied_pricing_unit_attrs:
      )
    end

    def cascade?
      ActiveModel::Type::Boolean.new.cast(params[:cascade_updates])
    end

    def process_minimum_commitment(plan, params)
      if params.present?
        minimum_commitment = plan.minimum_commitment ||
          Commitment.new(organization_id: plan.organization_id, plan:, commitment_type: "minimum_commitment")

        minimum_commitment.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
        minimum_commitment.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
        minimum_commitment.save!
      end
      plan.minimum_commitment.destroy! if params.blank? && plan.minimum_commitment

      if params[:tax_codes]
        taxes_result = Commitments::ApplyTaxesService.call(
          commitment: minimum_commitment,
          tax_codes: params[:tax_codes]
        )
        taxes_result.raise_if_error!
      end

      minimum_commitment
    end

    def process_charges(plan, params_charges)
      created_charges_ids = []

      hash_charges = params_charges.map { |c| c.to_h.deep_symbolize_keys }
      hash_charges.each do |payload_charge|
        charge = plan.charges.find_by(id: payload_charge[:id])

        if charge
          cascade_charge_update(charge, payload_charge)
          Charges::UpdateService.call(charge:, params: payload_charge).raise_if_error!

          next
        end

        create_charge_result = Charges::CreateService.call!(plan:, params: payload_charge)

        after_commit { cascade_charge_creation(create_charge_result.charge, payload_charge) }
        created_charges_ids.push(create_charge_result.charge.id)
      end

      # NOTE: Delete charges that are no more linked to the plan
      sanitize_charges(plan, hash_charges, created_charges_ids)
    end

    def sanitize_charges(plan, args_charges, created_charges_ids)
      args_charges_ids = args_charges.map { |c| c[:id] }.compact
      charges_ids = plan.charges.pluck(:id) - args_charges_ids - created_charges_ids
      plan.charges.where(id: charges_ids).find_each do |charge|
        after_commit { cascade_charge_removal(charge) }
        Charges::DestroyService.call(charge:)
      end
    end

    # NOTE: We should remove pending subscriptions
    #       if plan has been downgraded but amount cents became less than downgraded value. This pending subscription
    #       is not relevant in this case and downgrade should be ignored
    def process_downgraded_subscriptions
      return unless plan.subscriptions.active.exists?

      Subscription.where(previous_subscription: plan.subscriptions.active, status: :pending).find_each do |sub|
        sub.mark_as_canceled! if plan.amount_cents < sub.plan.amount_cents
      end
    end

    # NOTE: If new plan yearly amount is higher than its value before the update
    #       and there are pending subscriptions for the plan,
    #       this is a plan upgrade, old subscription must be terminated and billed
    #       new subscription with updated plan must be activated inmediately.
    def process_pending_subscriptions
      Subscription.where(plan:, status: :pending).find_each do |subscription|
        next unless subscription.previous_subscription

        if plan.yearly_amount_cents >= subscription.previous_subscription.plan.yearly_amount_cents
          Subscriptions::PlanUpgradeService.call(
            current_subscription: subscription.previous_subscription,
            plan: plan,
            params: {name: subscription.name}
          ).raise_if_error!
        end
      end
    end
  end
end
