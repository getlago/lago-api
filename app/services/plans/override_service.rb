# frozen_string_literal: true

module Plans
  class OverrideService < BaseService
    def initialize(plan:, params:)
      @plan = plan
      @params = params

      super
    end

    def call
      return result unless License.premium?

      ActiveRecord::Base.transaction do
        new_plan = plan.dup.tap do |p|
          p.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
          p.amount_currency = params[:amount_currency] if params.key?(:amount_currency)
          p.description = params[:description] if params.key?(:description)
          p.invoice_display_name = params[:invoice_display_name] if params.key?(:invoice_display_name)
          p.name = params[:name] if params.key?(:name)
          p.trial_period = params[:trial_period] if params.key?(:trial_period)
          p.parent_id = plan.id
        end
        new_plan.save!

        if params[:tax_codes]
          taxes_result = Plans::ApplyTaxesService.call(plan: new_plan, tax_codes: params[:tax_codes])
          return taxes_result unless taxes_result.success?
        end

        plan.charges.each do |charge|
          charge_params = (
            params[:charges].find { |p| p[:id] == charge.id } || {}
          ).merge(plan_id: new_plan.id)
          Charges::OverrideService.call(charge:, params: charge_params)
        end

        result.plan = new_plan
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :plan, :params
  end
end
