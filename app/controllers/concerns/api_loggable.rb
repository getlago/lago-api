# frozen_string_literal: true

module ApiLoggable
  extend ActiveSupport::Concern

  included do
    around_action :produce_api_log, if: -> { !request.get? }
  end

  def produce_api_log
    yield
    Utils::ApiLog.produce(request, response, organization: current_organization)
  ensure
    request.body.rewind
  end
end
