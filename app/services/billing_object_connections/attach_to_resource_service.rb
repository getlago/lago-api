# frozen_string_literal: true

module BillingObjectConnections
  class AttachToResourceService < BaseService
    Result = BaseResult[:billing_object_connections]

    INHERIT_BEHAVIOR = "inherit"

    def initialize(resource:, params:)
      @resource = resource
      @params = params
      super
    end

    def call
      return result unless params.key?(:connections)
      return result if connections.blank?

      ActiveRecord::Base.transaction do
        connections.each do |category, choice|
          next if choice.blank?

          apply_choice(category.to_s, choice)
        end
      end

      result.billing_object_connections = resource.billing_object_connections.reload
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      # raise_if_error! unwinds the transaction on an unresolvable code; the failure is returned
      # rather than propagated so `.call` keeps the BaseService contract.
      e.result
    end

    private

    attr_reader :resource, :params

    # See ValidateService: GraphQL supplies an InputObject, REST a plain Hash.
    def connections
      raw = params[:connections]
      return raw if raw.is_a?(Hash)

      raw.respond_to?(:to_hash) ? raw.to_hash : raw
    end

    def customer
      resource.customer
    end

    def apply_choice(category, choice)
      behavior = choice[:behavior].to_s

      if behavior == INHERIT_BEHAVIOR
        destroy_override(category)
      elsif behavior == BillingObjectConnection::BEHAVIORS[:skip]
        upsert_override(category, behavior: :skip, connection: nil)
      else
        connection = resolve_connection(category, choice[:code])

        if connection.nil?
          result.single_validation_failure!(field: :connections, error_code: "connection_not_found")
          result.raise_if_error!
        end

        upsert_override(category, behavior: :specific, connection:)
      end
    end

    def destroy_override(category)
      resource.billing_object_connections.find_by(category:)&.destroy!
    end

    def upsert_override(category, behavior:, connection:)
      override = resource.billing_object_connections.find_or_initialize_by(category:)

      override.organization_id = resource.organization_id
      override.behavior = behavior
      override.payment_provider_customer = nil
      override.integration_customer = nil

      if payment?(category)
        override.payment_provider_customer = connection
      else
        override.integration_customer = connection
      end

      override.save!
    end

    # Both foreign keys are optional on the model and the category/column pairing lives only in
    # ConnectionResolvable, so the mapping is mirrored here.
    def resolve_connection(category, code)
      return nil if code.blank? || customer.nil?

      if payment?(category)
        customer.payment_connection(code)
      else
        customer.integration_customers.find_by(category:, code:)
      end
    end

    def payment?(category)
      category == BillingObjectConnection::CATEGORIES[:payment]
    end
  end
end
