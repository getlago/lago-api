# frozen_string_literal: true

module Plans
  class CreateService < BaseService
    def initialize(args)
      @args = args
      super
    end

    activity_loggable(
      action: "plan.created",
      record: -> { result.plan }
    )

    def call
      plan = Plan.new(
        organization_id: args[:organization_id],
        name: args[:name],
        invoice_display_name: args[:invoice_display_name],
        code: args[:code],
        description: args[:description],
        interval: args[:interval]&.to_sym,
        pay_in_advance: args[:pay_in_advance],
        amount_cents: args[:amount_cents],
        amount_currency: args[:amount_currency],
        trial_period: args[:trial_period],
        bill_charges_monthly: bill_charges_monthly(args),
        bill_fixed_charges_monthly: bill_fixed_charges_monthly(args)
      )

      chargeables_validation_result = Plans::ChargeablesValidationService.call(
        organization: plan.organization,
        charges: args[:charges],
        fixed_charges: args[:fixed_charges]
      )
      return chargeables_validation_result if chargeables_validation_result.failure?

      ActiveRecord::Base.transaction do
        plan.save!

        if args[:tax_codes]
          taxes_result = Plans::ApplyTaxesService.call(plan:, tax_codes: args[:tax_codes])
          taxes_result.raise_if_error!
        end

        if args[:usage_thresholds].present? &&
            License.premium? &&
            plan.organization.progressive_billing_enabled?
          args[:usage_thresholds].each do |threshold_args|
            create_usage_threshold(plan, threshold_args)
          end
        end

        if args[:charges].present?
          args[:charges].each do |charge|
            new_charge = create_charge(plan, charge)

            if charge[:tax_codes].present?
              taxes_result = Charges::ApplyTaxesService.call(charge: new_charge, tax_codes: charge[:tax_codes])
              taxes_result.raise_if_error!
            end
          end
        end

        if args[:fixed_charges].present?
          args[:fixed_charges].each do |fixed_charge_args|
            FixedCharges::CreateService.call!(plan:, params: fixed_charge_args)
          end
        end

        if args[:minimum_commitment].present? && License.premium?
          minimum_commitment = args[:minimum_commitment]
          new_commitment = create_commitment(plan, minimum_commitment, :minimum_commitment)
          if minimum_commitment[:tax_codes].present?
            taxes_result = Commitments::ApplyTaxesService.call(
              commitment: new_commitment,
              tax_codes: minimum_commitment[:tax_codes]
            )
            taxes_result.raise_if_error!
          end
        end
      end

      result.plan = plan
      track_plan_created(plan)
      SendWebhookJob.perform_after_commit("plan.created", plan)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :args

    def create_commitment(plan, args, commitment_type)
      Commitment.create!(
        organization_id: plan.organization_id,
        plan:,
        commitment_type:,
        invoice_display_name: args[:invoice_display_name],
        amount_cents: args[:amount_cents]
      )
    end

    def create_usage_threshold(plan, args)
      usage_threshold = plan.usage_thresholds.new(
        organization_id: plan.organization_id,
        threshold_display_name: args[:threshold_display_name],
        amount_cents: args[:amount_cents],
        recurring: args[:recurring] || false
      )

      usage_threshold.save!
    end

    def create_charge(plan, args)
      charge = plan.charges.new(
        organization_id: plan.organization_id,
        billable_metric_id: args[:billable_metric_id],
        invoice_display_name: args[:invoice_display_name],
        charge_model: args[:charge_model],
        pay_in_advance: args[:pay_in_advance] || false,
        prorated: args[:prorated] || false
      )

      properties = args[:properties].presence || ChargeModels::BuildDefaultPropertiesService.call(args[:charge_model])
      charge.properties = ChargeModels::FilterPropertiesService.call(
        chargeable: charge,
        properties:
      ).properties

      if args[:filters].present?
        charge.save!
        ChargeFilters::CreateOrUpdateBatchService.call(
          charge:,
          filters_params: args[:filters].map(&:with_indifferent_access)
        ).raise_if_error!
      end

      if License.premium?
        charge.invoiceable = args[:invoiceable] unless args[:invoiceable].nil?
        charge.regroup_paid_fees = args[:regroup_paid_fees] if args.key?(:regroup_paid_fees)
        charge.min_amount_cents = args[:min_amount_cents] || 0
      end

      charge.save!

      AppliedPricingUnits::CreateService.call!(charge:, params: args[:applied_pricing_unit])

      charge
    end

    def bill_charges_monthly(args)
      return nil unless charges_billable_monthly?(args)

      args[:bill_charges_monthly] || false
    end

    def bill_fixed_charges_monthly(args)
      return nil unless charges_billable_monthly?(args)

      args[:bill_fixed_charges_monthly] || false
    end

    def charges_billable_monthly?(args)
      interval = args[:interval]&.to_sym

      %i[yearly semiannual].include?(interval)
    end

    def track_plan_created(plan)
      count_by_charge_model = plan.charges.group(:charge_model).count
      count_by_fixed_charge_model = plan.fixed_charges.group(:charge_model).count

      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: "plan_created",
        properties: {
          code: plan.code,
          name: plan.name,
          invoice_display_name: plan.invoice_display_name,
          description: plan.description,
          plan_interval: plan.interval,
          plan_amount_cents: plan.amount_cents,
          plan_period: plan.pay_in_advance ? "advance" : "arrears",
          trial: plan.trial_period,
          nb_charges: plan.charges.count,
          nb_standard_charges: count_by_charge_model["standard"] || 0,
          nb_percentage_charges: count_by_charge_model["percentage"] || 0,
          nb_graduated_charges: count_by_charge_model["graduated"] || 0,
          nb_package_charges: count_by_charge_model["package"] || 0,
          nb_fixed_charges: plan.fixed_charges.count,
          nb_standard_fixed_charges: count_by_fixed_charge_model["standard"] || 0,
          nb_graduated_fixed_charges: count_by_fixed_charge_model["graduated"] || 0,
          nb_volume_fixed_charges: count_by_fixed_charge_model["volume"] || 0,
          organization_id: plan.organization_id,
          parent_id: plan.parent_id
        }
      )
    end
  end
end
