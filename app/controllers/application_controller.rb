# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ApiResponses

  rescue_from ActionController::RoutingError, with: :not_found
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def health
    result = Utils::VersionService.new.version

    render(
      json: {
        version: result.version.number,
        github_url: result.version.github_url,
        message: 'Success',
      },
      status: :ok,
    )
  end

  def not_found
    not_found_error(resource: 'resource')
  end
end
