module ApiLoggable
  extend ActiveSupport::Concern

  included do
    around_action :produce_api_log, if: -> { !request.get? }
  end

  def produce_api_log
    yield
  end
end