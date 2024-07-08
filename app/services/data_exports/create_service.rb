# frozen_string_literal: true

module DataExports
  class CreateService < BaseService
    def initialize(organization:, user:, format:, resource_type:, resource_query:)
      @organization = organization
      @user = user
      @format = format
      @resource_type = resource_type
      @resource_query = resource_query || {}

      super(user)
    end

    def call
      data_export = DataExport.create!(
        organization:,
        membership:,
        format:,
        resource_type:,
        resource_query:
      )

      ExportResourcesJob.perform_later(data_export)

      result.data_export = data_export
      result
    end

    private

    attr_reader :organization, :user, :format, :resource_type, :resource_query

    def membership
      user.memberships.find_by(organization: organization)
    end
  end
end
