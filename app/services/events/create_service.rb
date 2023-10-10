# frozen_string_literal: true

module Events
  class CreateService < BaseService
    def initialize(organization:)
      @organization = organization
      super
    end

    def call(params:, timestamp:, metadata:)
      event = Event.new
      event.organization_id = organization.id
      event.code = params[:code]
      event.transaction_id = params[:transaction_id]
      event.external_customer_id = params[:external_customer_id]
      event.external_subscription_id = params[:external_subscription_id]
      event.properties = params[:properties] || {}
      event.metadata = metadata || {}
      event.timestamp = Time.zone.at(params[:timestamp] ? params[:timestamp].to_f : timestamp)
      event.save!

      result.event = event

      Events::PostProcessJob.perform_later(event:)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique
      result.single_validation_failure!(field: :transaction_id, error_code: 'value_already_exist')
    end

    private

    attr_reader :organization
  end
end
