# frozen_string_literal: true

class ApplicationController < ActionController::API
  wrap_parameters false

  include ApiResponses

  rescue_from ActionController::RoutingError, with: :not_found
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def health
    result = Utils::VersionService.new.version
    begin
      ActiveRecord::Base.connection.execute('')
      render(
        json: {
          version: result.version.number,
          github_url: result.version.github_url,
          message: 'Success'
        },
        status: :ok
      )
    rescue ActiveRecord::ActiveRecordError => e
      render(
        json: {
          version: result.version.number,
          github_url: result.version.github_url,
          message: 'Unhealthy',
          details: e.message
        },
        status: :internal_server_error
      )
    end
  end

  def not_found
    not_found_error(resource: 'resource')
  end

  def append_info_to_payload(payload)
    super
    payload[:organization_id] = current_organization&.id if defined? current_organization
  end
end
