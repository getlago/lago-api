# frozen_string_literal: true

module ApiLoggable
  extend ActiveSupport::Concern

  included do
    around_action :produce_api_log, unless: :produce_api_log?
  end

  module ClassMethods
    def skip_api_tracking!
      @skip_api_tracking = true
    end

    def skip_api_tracking?
      !!@skip_api_tracking
    end
  end

  def produce_api_log?
    request.get? || self.class.skip_api_tracking?
  end

  private

  def produce_api_log
    yield
    Utils::ApiLog.produce(request, response, organization: current_organization)
  ensure
    request.body.rewind
  end
end
