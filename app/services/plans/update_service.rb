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

      old_amount_cents = plan.amount_cents

      plan.name = params[:name] if params.key?(:name)
      plan.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
      plan.description = params[:description] if params.key?(:description)
      plan.amount_cents = params[:amount_cents] if params.key?(:amount_cents)

      # NOTE: Only name and description are editable if plan
      #       is attached to subscriptions
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
          return result.not_found_failure!(resource: 'billable_metrics')
        end
      end

      ActiveRecord::Base.transaction do
        plan.save!

        if params[:tax_codes]
          taxes_result = Plans::ApplyTaxesService.call(plan:, tax_codes: params[:tax_codes])
          taxes_result.raise_if_error!
        end

        process_charges(plan, params[:charges]) if params[:charges]

        if params.key?(:usage_thresholds) &&
            License.premium? &&
            plan.organization.premium_integrations.include?('progressive_billing')

          if params[:usage_thresholds].empty?
            plan.usage_thresholds.discard_all
          else
            process_usage_thresholds(plan, params[:usage_thresholds])
          end
        end

        process_minimum_commitment(plan, params[:minimum_commitment]) if params[:minimum_commitment] && License.premium?

        if old_amount_cents != plan.amount_cents
          process_downgraded_subscriptions
          process_pending_subscriptions
        end
      end

      cascade_subscription_fee_update(old_amount_cents)

      plan.invoices.draft.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations

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
        Plans::UpdateAmountJob.perform_later(plan: p, amount_cents: plan.amount_cents)
      end
    end

    def cascade?
      ActiveModel::Type::Boolean.new.cast(params[:cascade_updates])
    end

    def create_usage_threshold(plan, params)
      usage_threshold = plan.usage_thresholds.find_or_initialize_by(
        recurring: params[:recurring] || false,
        amount_cents: params[:amount_cents]
      )

      existing_recurring_threshold = plan.usage_thresholds.recurring.first

      if params[:recurring] && existing_recurring_threshold
        usage_threshold = existing_recurring_threshold
      end

      usage_threshold.threshold_display_name = params[:threshold_display_name]
      usage_threshold.amount_cents = params[:amount_cents]

      usage_threshold.save!
      usage_threshold
    end

    def create_charge(plan, params)
      charge = plan.charges.new(
        billable_metric_id: params[:billable_metric_id],
        invoice_display_name: params[:invoice_display_name],
        amount_currency: params[:amount_currency],
        charge_model: charge_model(params),
        pay_in_advance: params[:pay_in_advance] || false,
        prorated: params[:prorated] || false
      )

      properties = params[:properties].presence || Charges::BuildDefaultPropertiesService.call(charge.charge_model)
      charge.properties = Charges::FilterChargeModelPropertiesService.call(
        charge:,
        properties:
      ).properties

      if params[:filters].present?
        charge.save!
        ChargeFilters::CreateOrUpdateBatchService.call(
          charge:,
          filters_params: params[:filters].map(&:with_indifferent_access)
        ).raise_if_error!
      end

      if License.premium?
        charge.invoiceable = params[:invoiceable] unless params[:invoiceable].nil?
        charge.regroup_paid_fees = params[:regroup_paid_fees] if params.key?(:regroup_paid_fees)
        charge.min_amount_cents = params[:min_amount_cents] || 0
      end

      charge.save!

      if params[:tax_codes]
        taxes_result = Charges::ApplyTaxesService.call(charge:, tax_codes: params[:tax_codes])
        taxes_result.raise_if_error!
      end

      charge
    end

    def charge_model(params)
      model = params[:charge_model]&.to_sym
      return if model == :graduated_percentage && !License.premium?

      model
    end

    def process_minimum_commitment(plan, params)
      if params.present?
        minimum_commitment = plan.minimum_commitment || Commitment.new(plan:, commitment_type: 'minimum_commitment')

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

    def process_usage_thresholds(plan, params_thresholds)
      created_thresholds_ids = []

      hash_thresholds = params_thresholds.map { |c| c.to_h.deep_symbolize_keys }
      hash_thresholds.each do |payload_threshold|
        usage_threshold = plan.usage_thresholds.find_by(id: payload_threshold[:id])

        if usage_threshold
          if payload_threshold.key?(:threshold_display_name)
            usage_threshold.threshold_display_name = payload_threshold[:threshold_display_name]
          end

          if payload_threshold.key?(:amount_cents)
            usage_threshold.amount_cents = payload_threshold[:amount_cents]
          end

          if payload_threshold.key?(:recurring)
            usage_threshold.recurring = payload_threshold[:recurring]
          end

          # This means that in the UI we just removed an existing threshold
          # and then just re-added a threshold (which no longer has an id) with the same amount
          # so we discard the existing one and we're inserting a new one instead
          if !usage_threshold.valid? && usage_threshold.errors.where(:amount_cents, :taken).present?
            usage_threshold.discard!
          else
            usage_threshold.save!
            next
          end
        end

        plan = plan.reload

        created_threshold = create_usage_threshold(plan, payload_threshold)
        created_thresholds_ids.push(created_threshold.id)
      end

      # NOTE: Delete thresholds that are no more linked to the plan
      sanitize_thresholds(plan, hash_thresholds, created_thresholds_ids)
    end

    def process_charges(plan, params_charges)
      created_charges_ids = []

      hash_charges = params_charges.map { |c| c.to_h.deep_symbolize_keys }
      hash_charges.each do |payload_charge|
        charge = plan.charges.find_by(id: payload_charge[:id])

        if charge
          charge.charge_model = payload_charge[:charge_model] unless plan.attached_to_subscriptions?

          properties = payload_charge.delete(:properties).presence || Charges::BuildDefaultPropertiesService.call(
            payload_charge[:charge_model]
          )

          charge.update!(
            invoice_display_name: payload_charge[:invoice_display_name],
            properties: Charges::FilterChargeModelPropertiesService.call(
              charge:,
              properties:
            ).properties
          )

          filters = payload_charge.delete(:filters)
          unless filters.nil?
            ChargeFilters::CreateOrUpdateBatchService.call(
              charge:,
              filters_params: filters.map(&:with_indifferent_access)
            ).raise_if_error!
          end

          tax_codes = payload_charge.delete(:tax_codes)
          if tax_codes
            taxes_result = Charges::ApplyTaxesService.call(charge:, tax_codes:)
            taxes_result.raise_if_error!
          end

          # NOTE: charges cannot be edited if plan is attached to a subscription
          unless plan.attached_to_subscriptions?
            invoiceable = payload_charge.delete(:invoiceable)
            min_amount_cents = payload_charge.delete(:min_amount_cents)

            charge.invoiceable = invoiceable if License.premium? && !invoiceable.nil?
            charge.min_amount_cents = min_amount_cents || 0 if License.premium?

            charge.update!(payload_charge)
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
      args_charges_ids = args_charges.map { |c| c[:id] }.compact
      charges_ids = plan.charges.pluck(:id) - args_charges_ids - created_charges_ids
      plan.charges.where(id: charges_ids).find_each { |charge| discard_charge!(charge) }
    end

    def sanitize_thresholds(plan, args_thresholds, created_thresholds_ids)
      args_thresholds_ids = args_thresholds.map { |c| c[:id] }.compact
      thresholds_ids = plan.usage_thresholds.pluck(:id) - args_thresholds_ids - created_thresholds_ids
      plan.usage_thresholds.where(id: thresholds_ids).discard_all
    end

    def discard_charge!(charge)
      charge.discard!

      charge.filter_values.discard_all
      charge.filters.discard_all
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

    # NOTE: We should remove pending subscriptions
    #       if plan has been downgraded but amount cents of pending plan became higher than original plan.
    #       This pending subscription is not relevant in this case and downgrade should be ignored
    def process_pending_subscriptions
      Subscription.where(plan:, status: :pending).find_each do |sub|
        sub.mark_as_canceled! if plan.amount_cents > sub.previous_subscription.plan.amount_cents
      end
    end
  end
end
