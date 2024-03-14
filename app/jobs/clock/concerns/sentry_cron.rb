# frozen_string_literal: true

module SentryCronConcern
  extend ActiveSupport::Concern
  include Sentry::Cron::MonitorCheckIns
  
  included do
    def self.mixin_sentry_cron(sentry)
      if ENV['SENTRY_ENABLE_CRONS']
        sentry_monitor_check_ins(
          slug: sentry.slug,
          monitor_config: Sentry::Cron::MonitorConfig.from_crontab(sentry.cron)
        )
      end
    end
  end
end
