# frozen_string_literal: true

module Admin
  module Organizations
    class CreateService < BaseService
      def initialize(params:)
        @params = params
        super
      end

      def call
        organization = Organization.new(organization_params)

        unless organization.save
          return result.validation_failure!(errors: organization.errors)
        end

        # Enable premium features if requested
        if ActiveModel::Type::Boolean.new.cast(params[:premium_features])
          organization.update!(premium_features: true)
        end

        # Create default API key for the organization
        api_key = organization.api_keys.create!(
          name: 'Default API Key',
          key: SecureRandom.uuid.delete('-')
        )

        result.organization = organization
        result.api_key = api_key
        result
      end

      private

      attr_reader :params

      def organization_params
        {
          name: params[:name],
          email: params[:email],
          country: params[:country],
          address_line1: params[:address_line1],
          address_line2: params[:address_line2],
          state: params[:state],
          zipcode: params[:zipcode],
          city: params[:city],
          timezone: params[:timezone] || 'UTC',
          billing_configuration: params[:billing_configuration] || {}
        }
      end
    end
  end
end
