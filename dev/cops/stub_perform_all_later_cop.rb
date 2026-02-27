# frozen_string_literal: true

require "rubocop"

module Cops
  class StubPerformAllLaterCop < ::RuboCop::Cop::Base
    MSG = "Avoid stubbing `perform_all_later` on `ApplicationJob` as it silences the runtime uniqueness guard."

    # Matches:
    #   allow(ApplicationJob).to receive(:perform_all_later)
    #   expect(ApplicationJob).to have_received(:perform_all_later)
    #   expect(ApplicationJob).not_to have_received(:perform_all_later)
    def_node_matcher :stub_perform_all_later?, <<~PATTERN
      (send
        (send nil? {:allow :expect} (const nil? :ApplicationJob))
        {:to :not_to :to_not}
        (send nil? {:receive :have_received} (sym :perform_all_later))
        ...)
    PATTERN

    def self.badge
      @badge ||= ::RuboCop::Cop::Badge.for("Lago/StubPerformAllLater") # rubocop:disable ThreadSafety/ClassInstanceVariable
    end

    def on_send(node)
      return unless stub_perform_all_later?(node)

      add_offense(node)
    end
  end
end
