# frozen_string_literal: true

module Organizations
  class CreateService < BaseService
    def initialize(params)
      @params = params
      super
    end

    def call
      organization = Organization.new(
        params.slice(:name, :document_numbering)
      )

      ActiveRecord::Base.transaction do
        # TODO: remove when we do not support document_numbering per organization
        organization.save!
        organization.api_keys.create!
        if params[:document_numbering]
          params[:document_numbering] = "per_billing_entity" if params[:document_numbering] == "per_organization"
        end
        params[:code] = params[:name]&.parameterize(separator: "_") if params[:code].blank?
        BillingEntities::CreateService.call(organization: organization, params: params)
      end

      result.organization = organization
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :params
  end
end
