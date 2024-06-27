module DataExports
  class ExportResourcesJob < ApplicationJob
    queue_as :data_export

    def perform(data_export)
      ExportResourcesService.call(data_export:).raise_if_error!
    end
  end
end
