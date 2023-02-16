# frozen_string_literal: true

module AppliedAddOns
  class CreateService < BaseService
    def initialize(customer:, add_on:, params:)
      @customer = customer
      @add_on = add_on
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'add_on') unless add_on

      applied_add_on = AppliedAddOn.new(
        customer:,
        add_on:,
        amount_cents: params[:amount_cents] || add_on.amount_cents,
        amount_currency: params[:amount_currency] || add_on.amount_currency,
      )

      ActiveRecord::Base.transaction do
        currency_result = Customers::UpdateService.new(nil).update_currency(
          customer:,
          currency: params[:amount_currency] || add_on.amount_currency,
        )
        return currency_result unless currency_result.success?

        applied_add_on.save!
      end

      BillAddOnJob.perform_later(applied_add_on, Time.current.to_i)

      result.applied_add_on = applied_add_on
      track_applied_add_on_created(result.applied_add_on)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :customer, :add_on, :params

    def track_applied_add_on_created(applied_add_on)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'applied_add_on_created',
        properties: {
          customer_id: applied_add_on.customer.id,
          addon_code: applied_add_on.add_on.code,
          addon_name: applied_add_on.add_on.name,
        },
      )
    end
  end
end
