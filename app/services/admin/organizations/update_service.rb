# frozen_string_literal: true

module Admin
  module Organizations
    class UpdateService < ::BaseService
      def initialize(organization:, params:)
        @organization = organization
        @params = params
  
        super(nil)
      end

      def call
        organization.name = params[:name] if params.key?(:name)

        organization.save!

        result.organization = organization
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :organization, :params
    end
  end
end
