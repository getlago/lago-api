# frozen_string_literal: true

module AppliedAddOns
  class CreateService < BaseService
    def create(**args)
      @customer = Customer.find_by(
        id: args[:customer_id],
        organization_id: args[:organization_id],
      )

      @add_on = AddOn.find_by(
        id: args[:add_on_id],
        organization_id: args[:organization_id],
      )

      process_creation(
        amount_cents: args[:amount_cents] || add_on&.amount_cents,
        amount_currency: args[:amount_currency] || add_on&.amount_currency,
      )
    end

    def create_from_api(organization:, args:)
      @customer = Customer.find_by(
        external_id: args[:external_customer_id],
        organization_id: organization.id,
      )

      @add_on = AddOn.find_by(
        code: args[:add_on_code],
        organization_id: organization.id,
      )

      process_creation(
        amount_cents: args[:amount_cents] || add_on&.amount_cents,
        amount_currency: args[:amount_currency] || add_on&.amount_currency,
      )
    end

    private

    attr_reader :customer, :add_on

    def check_preconditions
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'add_on') unless add_on
    end

    def process_creation(amount_cents:, amount_currency:)
      check_preconditions
      return result if result.error

      applied_add_on = AppliedAddOn.new(
        customer: customer,
        add_on: add_on,
        amount_cents: amount_cents,
        amount_currency: amount_currency,
      )

      ActiveRecord::Base.transaction do
        currency_result = Customers::UpdateService.new(nil).update_currency(
          customer: customer,
          currency: amount_currency,
        )
        return currency_result unless currency_result.success?

        applied_add_on.save!
      end

      BillAddOnJob.perform_later(
        applied_add_on,
        Time.zone.now.to_date,
      )

      result.applied_add_on = applied_add_on
      track_applied_add_on_created(result.applied_add_on)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

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
