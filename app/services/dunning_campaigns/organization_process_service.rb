# frozen_string_literal: true

module DunningCampaigns
  class OrganizationProcessService < BaseService
    Result = BaseResult[:total_jobs]
    BATCH_SIZE = 500

    def initialize(organization)
      @organization = organization
      super()
    end

    def call
      return result unless organization&.auto_dunning_enabled?

      jobs = []
      result.total_jobs = 0
      Invoice.where(organization:).payment_overdue.distinct.pluck(:customer_id).each do |id|
        jobs << DunningCampaigns::ProcessCustomerJob.new(Customer.new(id: id))

        if jobs.size == BATCH_SIZE
          ActiveJob.perform_all_later(jobs)
          result.total_jobs += jobs.size
          jobs.clear
        end
      end
      ActiveJob.perform_all_later(jobs)
      result.total_jobs += jobs.size

      result
    end

    private

    attr_reader :organization
  end
end
