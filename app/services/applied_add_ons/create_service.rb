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

    def check_preconditions(amount_currency:)
      return result.fail!(code: 'missing_argument', message: 'unable_to_find_customer') if customer.blank?
      return result.fail!(code: 'missing_argument', message: 'add_on_does_not_exist') if add_on.blank?
      return result.fail!(code: 'no_active_subscription') unless active_subscription?
      return result.fail!(code: 'currencies_does_not_match') unless applicable_currency?(amount_currency)
    end

    def process_creation(amount_cents:, amount_currency:)
      check_preconditions(amount_currency: amount_currency)
      return result if result.error

      applied_add_on = AppliedAddOn.create!(
        customer: customer,
        add_on: add_on,
        amount_cents: amount_cents,
        amount_currency: amount_currency,
      )

      BillAddOnJob.perform_later(
        active_subscription,
        applied_add_on,
        Time.zone.now.to_date,
      )

      result.applied_add_on = applied_add_on
      track_applied_add_on_created(result.applied_add_on)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def active_subscription?
      active_subscription.present?
    end

    def applicable_currency?(currency)
      active_subscription.plan.amount_currency == currency
    end

    def active_subscription
      @active_subscription ||= customer.active_subscription
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
