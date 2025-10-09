# frozen_string_literal: true

module Utils
  class ActivityLogMiddleware < BaseMiddleware
    def call
      if service_instance.try(:produce_activity_log?)
        klass = service_instance.class
        action = klass.activity_log_config[:action]
        after_commit = klass.activity_log_config[:after_commit]
        kwargs = {after_commit:}.compact

        case action
        when /updated/
          record = service_instance.instance_exec(&klass.activity_log_config[:record])
          Utils::ActivityLog.produce(record, action, **kwargs) { super }
        else
          super.tap do |result|
            record = service_instance.instance_exec(&klass.activity_log_config[:record])

            Utils::ActivityLog.produce(record, action, **kwargs) { result }
          end
        end
      else
        super
      end
    end
  end
end
