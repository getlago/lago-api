# frozen_string_literal: true

module Organizations
  class CreateService < BaseService
    Result = BaseResult[:organization]

    ORGANIZATION_ATTRIBUTES = %i[
      name document_numbering premium_integrations feature_flags slug self_serve environment production_organization_id
    ].freeze

    def initialize(params)
      @params = params
      super
    end

    def call
      organization = Organization.new(params.slice(*ORGANIZATION_ATTRIBUTES))

      if ActiveModel::Type::Boolean.new.cast(ENV["LAGO_CLICKHOUSE_ENABLED"]) && ENV["LAGO_DEFAULT_EVENT_STORE"] == "clickhouse"
        organization.clickhouse_events_store = true
      end

      ActiveRecord::Base.transaction do
        organization.save!
        organization.api_keys.create!
        BillingEntities::CreateService.call!(organization:, params: billing_entity_params(organization))
      end

      result.organization = organization
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, "index_organizations_on_slug" => :slug)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :params

    # Built anew, so the caller's hash is never changed and only these fields reach the billing entity.
    def billing_entity_params(organization)
      entity_params = params.slice(:name, :code, :document_numbering, :timezone)
      # TODO: remove when we do not support document_numbering per organization
      entity_params[:document_numbering] = "per_billing_entity" if entity_params[:document_numbering].to_s == "per_organization"
      entity_params[:code] = entity_params[:name]&.parameterize(separator: "_") if entity_params[:code].blank?
      # NOTE: ensure first billing entity has the same id as the organization to ease the migration to multi entities.
      entity_params.merge(id: organization.id)
    end
  end
end
