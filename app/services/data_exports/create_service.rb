module DataExports
  class CreateService < BaseService
    def initialize(user:, format:, resource_type:, resource_query:)
      @user = user
      @format = format
      @resource_type = resource_type
      @resource_query = resource_query

      super(user)
    end

    def call
      data_export = DataExport.create!(user:, format:, resource_type:, resource_query:)
      ExportResourcesJob.perform_later(data_export)

      result.data_export = data_export
      result
    end

    private

    attr_reader :user, :format, :resource_type, :resource_query
  end
end
