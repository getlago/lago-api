# frozen_string_literal: true

require "rubocop"

module Cops
  class ActiveJobPerformAllLaterCop < ::RuboCop::Cop::Base
    MSG = "Avoid using `ActiveJob.perform_all_later`. Use `ApplicationJob.perform_all_later` instead."

    def_node_matcher :active_job_perform_all_later?, <<~PATTERN
      (send (const nil? :ActiveJob) :perform_all_later ...)
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/ActiveJobPerformAllLater") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return unless active_job_perform_all_later?(node)

      add_offense(node)
    end
  end
end
