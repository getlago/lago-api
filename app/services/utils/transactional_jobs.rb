# frozen_string_literal: true

module Utils
  module TransactionalJobs
    extend ActiveSupport::Concern

    included do
      def pending_jobs
        @pending_jobs ||= []
      end

      def perform_later(job_class:, arguments:)
        return job_class.perform_later(*arguments) unless ActiveRecord::Base.connection.transaction_open?

        pending_jobs << {job_class:, arguments:}
      end

      def perform_pending_jobs
        pending_jobs.each do |job|
          job[:job_class].perform_later(*job[:arguments])
        end
      end
    end
  end
end
