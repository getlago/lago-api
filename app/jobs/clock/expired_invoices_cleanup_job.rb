# app/jobs/expired_invoices_cleanup_job.rb
class ExpiredInvoicesCleanupJob < ApplicationJob
  queue_as :default

  def perform()
    expired_invoices = Invoice.open.where('created_at < ?', 90.days.ago)
    expired_invoices.find_each do |invoice|
      invoice.destroy
    end

    # delete the wallet transaction
  end
end
