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
        bill_charges_monthly: (args[:interval]&.to_sym == :yearly) ? args[:bill_charges_monthly] || false : nil,
        bill_fixed_charges_monthly: (args[:interval]&.to_sym == :yearly) ? args[:bill_fixed_charges_monthly] || false : nil
      )

      # Validates billable metrics
      if args[:charges].present?
        metric_ids = args[:charges].map { |c| c[:billable_metric_id] }.uniq
        if metric_ids.present? && plan.organization.billable_metrics.where(id: metric_ids).count != metric_ids.count
          return result.not_found_failure!(resource: "billable_metrics")
        end
      end

      # Validates fixed charges
      if args[:fixed_charges].present?
        add_on_ids = args[:fixed_charges].map { |c| c[:add_on_id] }.uniq
        if add_on_ids.present? && plan.organization.add_ons.where(id: add_on_ids).count != add_on_ids.count
          return result.not_found_failure!(resource: "add_ons")
        end
      end

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
          args[:fixed_charges].each do |fixed_charge|
            new_fixed_charge = create_fixed_charge(plan, fixed_charge)
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

      properties = args[:properties].presence || Charges::BuildDefaultPropertiesService.call(args[:charge_model])
      charge.properties = Charges::FilterChargeModelPropertiesService.call(
        charge:,
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

    def track_plan_created(plan)
      count_by_charge_model = plan.charges.group(:charge_model).count

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
          organization_id: plan.organization_id,
          parent_id: plan.parent_id
        }
      )
    end

    def create_fixed_charge(plan, args)
      fixed_charge = plan.fixed_charges.new(
        organization_id: plan.organization_id,
        add_on_id: args[:add_on_id],
        invoice_display_name: args[:invoice_display_name],
        charge_model: args[:charge_model],
        pay_in_advance: args[:pay_in_advance] || false,
        prorated: args[:prorated] || false,
        units: args[:units] || 1
      )

      properties = args[:properties].presence || FixedCharges::BuildDefaultPropertiesService.call(args[:charge_model])
      fixed_charge.properties = FixedCharges::FilterChargeModelPropertiesService.call(
        fixed_charge:,
        properties:
      ).properties

      fixed_charge.save!

      fixed_charge
    end
  end
end
