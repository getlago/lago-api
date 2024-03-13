# frozen_string_literal: true

module Clock
  class RefreshDraftInvoicesJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_refresh_draft_invoices', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('*/5 * * * *')
    end

    def perform
      Invoice.ready_to_be_refreshed.find_each do |invoice|
        Invoices::RefreshDraftJob.perform_later(invoice)
      end
    end
  end
end
