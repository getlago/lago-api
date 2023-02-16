# frozen_string_literal: true

module Plans
  class UpdateService < BaseService
    def initialize(plan:, params:)
      @plan = plan
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: 'plan') unless plan

      plan.name = params[:name] if params.key?(:name)
      plan.description = params[:description] if params.key?(:description)

      # NOTE: Only name and description are editable if plan
      #       is attached to subscriptions
      unless plan.attached_to_subscriptions?
        plan.code = params[:code] if params.key?(:code)
        plan.interval = params[:interval].to_sym if params.key?(:interval)
        plan.pay_in_advance = params[:pay_in_advance] if params.key?(:pay_in_advance)
        plan.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
        plan.amount_currency = params[:amount_currency] if params.key?(:amount_currency)
        plan.trial_period = params[:trial_period] if params.key?(:trial_period)
        plan.bill_charges_monthly = bill_charges_monthly?
      end

      if params[:charges].present?
        metric_ids = params[:charges].map { |c| c[:billable_metric_id] }.uniq
        if metric_ids.present? && organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
          return result.not_found_failure!(resource: 'billable_metrics')
        end
      end

      ActiveRecord::Base.transaction do
        plan.save!

        process_charges(plan, params[:charges] || [])
      end

      result.plan = plan
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan, :params

    delegate :organization, to: :plan

    def bill_charges_monthly?
      return unless params[:interval]&.to_sym == :yearly

      params[:bill_charges_monthly] || false
    end

    def create_charge(plan, params)
      plan.charges.create!(
        billable_metric_id: params[:billable_metric_id],
        amount_currency: params[:amount_currency],
        charge_model: params[:charge_model]&.to_sym,
        properties: params[:properties] || {},
        group_properties: (params[:group_properties] || []).map { |gp| GroupProperty.new(gp) },
      )
    end

    def process_charges(plan, params_charges)
      created_charges_ids = []

      hash_charges = params_charges.map { |c| c.to_h.deep_symbolize_keys }
      hash_charges.each do |payload_charge|
        charge = Charge.find_by(id: payload_charge[:id])

        if charge
          # NOTE: charges cannot be edited if plan is attached to a subscription
          unless plan.attached_to_subscriptions?
            payload_charge[:group_properties]&.map! { |gp| GroupProperty.new(gp) }
            charge.update(payload_charge)
            charge
          end

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
      charges_ids.each { |id| discard_charge!(Charge.find_by(id:)) }
    end

    def discard_charge!(charge)
      draft_invoice_ids = Invoice.draft.joins(plans: [:charges])
        .where(charges: { id: charge.id }).distinct.pluck(:id)

      charge.discard!
      charge.group_properties.discard_all

      # NOTE: Refresh all draft invoices asynchronously.
      Invoices::RefreshBatchJob.perform_later(draft_invoice_ids)
    end
  end
end
