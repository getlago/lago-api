# frozen_string_literal: true

module ApiLoggable
  extend ActiveSupport::Concern

  included do
    around_action :produce_api_log, if: :produce_api_log?

    # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    class_attribute :skip_audit_logs, instance_writer: false, default: false
    # rubocop:enable ThreadSafety/ClassAndModuleAttributes
  end

  module ClassMethods
    def skip_audit_logs!
      self.skip_audit_logs = true
    end

    def skip_audit_logs?
      skip_audit_logs
    end
  end

  def produce_api_log?
    !(request.get? || skip_audit_logs?)
  end

  private

  def produce_api_log
    yield
    Utils::ApiLog.produce(request, response, organization: current_organization)
  ensure
    request.body.rewind
  end
end
