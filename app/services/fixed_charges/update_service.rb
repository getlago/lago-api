# frozen_string_literal: true

module FixedCharges
  class UpdateService < BaseService
    def initialize(fixed_charge:, params:, cascade_options: {}, fixed_charges_affect_immediately: false)
      @fixed_charge = fixed_charge
      @params = params.to_h.deep_symbolize_keys
      @cascade_options = cascade_options
      @cascade = cascade_options[:cascade]
      @fixed_charges_affect_immediately = fixed_charges_affect_immediately

      super
    end

    def call
      return result.not_found_failure!(resource: "fixed_charge") unless fixed_charge
      return result if cascade && fixed_charge.charge_model != params[:charge_model]

      ActiveRecord::Base.transaction do
        fixed_charge.charge_model = params[:charge_model] unless plan.attached_to_subscriptions?
        fixed_charge.invoice_display_name = params[:invoice_display_name] unless cascade
        units_difference = params[:units] - fixed_charge.units
        fixed_charge.units = params[:units] if params.key?(:units)

        if !cascade || cascade_options[:equal_properties]
          properties = params.delete(:properties).presence || FixedCharges::BuildDefaultPropertiesService.call(
            params[:charge_model]
          )
          fixed_charge.properties = FixedCharges::FilterChargeModelPropertiesService.call(fixed_charge:, properties:).properties
        end

        fixed_charge.save!
        result.fixed_charge = fixed_charge
        issue_unit_events(units_difference) if fixed_charges_affect_immediately

        # In cascade mode it is allowed only to change properties
        unless cascade
          fixed_charge.update!(params)
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :fixed_charge, :params, :cascade_options, :cascade, :fixed_charges_affect_immediately

    delegate :plan, to: :fixed_charge

    def issue_unit_events(units)
      puts '-' * 100
      plan.subscriptions.active.find_each do |subscription|
        FixedCharges::EmitEventsService.call!(fixed_charge:, subscription:, units:)
      end
    end
  end
end
