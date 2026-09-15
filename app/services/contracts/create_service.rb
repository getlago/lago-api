# frozen_string_literal: true

module Contracts
  # Records a new agreement. The plan is optional by design: a plan-less
  # contract prices through directly attached rate cards. The contract is
  # active when its start has arrived, pending when it starts in the future
  # — lifecycle state lives in the status, the dates only carry the window.
  class CreateService < BaseService
    include CustomerTimezone

    Result = BaseResult[:contract, :payment_method]

    def initialize(organization:, params:)
      @organization = organization
      @params = params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      if params[:plan_code].present? && catalog_plan.nil?
        return result.not_found_failure!(resource: "plan")
      end

      # Date columns: a malformed value would silently cast to nil instead of
      # failing, so formats are rejected explicitly.
      %i[billing_anchor_date started_at ended_at].each do |field|
        if params[field].present? && !Utils::Datetime.valid_format?(params[field])
          return result.single_validation_failure!(field:, error_code: "value_is_invalid")
        end
      end

      # A window that already closed cannot be created: nothing would ever
      # terminate it, leaving a zombie active contract.
      if params[:ended_at].present? && ended_at_in_customer_timezone <= Time.current
        return result.single_validation_failure!(field: :ended_at, error_code: "already_ended")
      end

      # One live agreement per external id. Replacement flows (upgrade,
      # downgrade, renewal) will create their pending sibling explicitly when
      # they exist; a blind second create is a mistake, not a replacement.
      # Advisory under concurrency — the partial unique index closes the race.
      if organization.contracts.where(status: %w[pending active], external_id: params[:external_id]).exists?
        return result.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
      end

      if params[:billing_entity_id].present? && billing_entity.nil?
        return result.not_found_failure!(resource: "billing_entity")
      end

      if payment_method_params[:payment_method_id].present? && payment_method.nil?
        return result.not_found_failure!(resource: "payment_method")
      end

      # Rejects contradictory combinations (e.g. a manual type with a concrete
      # payment method), matching the subscription semantics.
      result.payment_method = payment_method
      return result unless PaymentMethods::ValidateService.new(result, payment_method: params[:payment_method]).valid?

      started_at = params[:started_at].present? ? started_at_in_customer_timezone : Time.current

      ActiveRecord::Base.transaction do
        contract = organization.contracts.create!(
          customer:,
          catalog_plan:,
          billing_entity:,
          external_id: params[:external_id],
          name: params[:name],
          billing_time: params[:billing_time].presence || "calendar",
          billing_anchor_date: params[:billing_anchor_date],
          purchase_order_number: params[:purchase_order_number],
          payment_method:,
          started_at:,
          ended_at: ended_at_in_customer_timezone,
          status: started_at.future? ? :pending : :active,
          # NOT NULL columns with DB defaults: only set when given.
          **optional_settings
        )

        Contracts::MaterializeRateCardsService.call!(contract:) if contract.catalog_plan

        result.contract = contract
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      # A concurrent create won the race past the advisory check; same answer
      # as the check itself. Any other uniqueness violation in the transaction
      # stays loud instead of masquerading as a duplicate external id.
      raise unless e.message.include?("index_contracts_on_live_external_id")

      result.single_validation_failure!(field: :external_id, error_code: "value_already_exists")
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :organization, :params

    def customer
      @customer ||= organization.customers.find_by(external_id: params[:external_customer_id])
    end

    def catalog_plan
      @catalog_plan ||= organization.catalog_plans.find_by(code: params[:plan_code])
    end

    # Explicit billing-entity override; nil (no id) inherits the customer's.
    def billing_entity
      return @billing_entity if defined?(@billing_entity)

      @billing_entity = params[:billing_entity_id].present? ? organization.billing_entities.find_by(id: params[:billing_entity_id]) : nil
    end

    # Nested payment-method reference input {payment_method_id, payment_method_type}.
    def payment_method_params
      params[:payment_method] || {}
    end

    # Payment methods are scoped to the customer.
    def payment_method
      return @payment_method if defined?(@payment_method)

      @payment_method = payment_method_params[:payment_method_id].present? ? customer.payment_methods.find_by(id: payment_method_params[:payment_method_id]) : nil
    end

    def optional_settings
      settings = {}
      settings[:consolidate_invoice] = params[:consolidate_invoice] unless params[:consolidate_invoice].nil?
      settings[:payment_method_type] = payment_method_params[:payment_method_type] if payment_method_params[:payment_method_type].present?
      settings
    end

    # Read through the CustomerTimezone suffix: a datetime without an offset
    # means the customer's wall clock, not the application's —
    # String#in_time_zone parses a naive value in the customer's zone and
    # respects explicit offsets. Nil when the param is absent.
    def started_at
      params[:started_at].presence
    end

    def ended_at
      params[:ended_at].presence
    end
  end
end
