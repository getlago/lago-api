# frozen_string_literal: true

module Clock
  class FinalizeInvoicesJob < ApplicationJob
    include Sentry::Cron::MonitorCheckIns

    queue_as 'clock'

    if ENV['SENTRY_ENABLE_CRONS']
      sentry_monitor_check_ins slug: 'lago_finalize_invoices', monitor_config: Sentry::Cron::MonitorConfig.from_crontab('20 */1 * * *')
    end

    def perform
      Invoice.ready_to_be_finalized.each do |invoice|
        Invoices::FinalizeJob.perform_later(invoice)
      end
    end
  end
end
