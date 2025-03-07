# frozen_string_literal: true

class ApplicationController < ActionController::API
  wrap_parameters false

  include ApiResponses

  rescue_from ActionController::RoutingError, with: :not_found
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def health
    ActiveRecord::Base.connection.execute("")
    render(
      json: {
        version: LAGO_VERSION.number,
        github_url: LAGO_VERSION.github_url,
        message: "Success"
      },
      status: :ok
    )
  rescue ActiveRecord::ActiveRecordError => e
    render(
      json: {
        version: LAGO_VERSION.number,
        github_url: LAGO_VERSION.github_url,
        message: "Unhealthy",
        details: e.message
      },
      status: :internal_server_error
    )
  end

  def not_found
    not_found_error(resource: "resource")
  end

  def append_info_to_payload(payload)
    super
    payload[:level] =
      case payload[:status]
      when 200..299
        "success"
      when 400..499
        "warn"
      when 500..599
        "error"
      end
    payload[:organization_id] = current_organization&.id if defined? current_organization
  rescue
    # NOTE: Rescue potential errors on JWT token, it should break later to avoid bad responses on GraphQL
  end
end
